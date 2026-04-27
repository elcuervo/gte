use crate::error::{GteError, Result};
use crate::model_config::{ExtractorMode, ModelConfig};
use crate::pipeline::{extract_output_tensor, InputTensors};
use crate::postprocess::mean_pool;
use crate::tokenizer::Tokenized;
use ndarray::{Array2, Ix2};
use ort::execution_providers::{
    CoreMLExecutionProvider, ExecutionProviderDispatch, XNNPACKExecutionProvider,
};
use ort::session::Session;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Condvar, Mutex};

pub fn build_session<P: AsRef<Path>>(model_path: P, config: &ModelConfig) -> Result<Session> {
    let opt_level = match config.optimization_level {
        0 => ort::session::builder::GraphOptimizationLevel::Disable,
        1 => ort::session::builder::GraphOptimizationLevel::Level1,
        2 => ort::session::builder::GraphOptimizationLevel::Level2,
        _ => ort::session::builder::GraphOptimizationLevel::Level3,
    };

    fn ort_err(e: impl std::fmt::Display) -> GteError { GteError::Ort(e.to_string()) }

    let mut builder = Session::builder().map_err(ort_err)?
        .with_optimization_level(opt_level).map_err(ort_err)?
        .with_memory_pattern(true).map_err(ort_err)?;

    let providers = preferred_execution_providers(config.execution_providers.as_deref());
    if !providers.is_empty() {
        builder = builder.with_execution_providers(providers).map_err(ort_err)?;
    }

    if config.num_threads > 0 {
        builder = builder.with_intra_threads(config.num_threads).map_err(ort_err)?;
        builder = builder.with_inter_threads(config.num_threads).map_err(ort_err)?;
    }

    builder.commit_from_file(model_path).map_err(ort_err)
}

// ---------------------------------------------------------------------------
// Session pool
// ---------------------------------------------------------------------------

const AUTO_THREAD_POOL_CAP: usize = 6;

/// Keep enough sessions to cover the configured thread budget without
/// oversubscribing CPU parallelism. In ORT auto-thread mode (`num_threads == 0`)
/// we still keep a modest pool because request-level concurrency benefits from
/// more than one session even when ORT manages thread counts internally.
fn pool_capacity(num_threads: usize) -> usize {
    let available_parallelism = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(1);
    pool_capacity_with_parallelism(num_threads, available_parallelism)
}

fn pool_capacity_with_parallelism(num_threads: usize, available_parallelism: usize) -> usize {
    if available_parallelism == 0 {
        return 1;
    }

    if num_threads == 0 {
        return available_parallelism.clamp(1, AUTO_THREAD_POOL_CAP);
    }

    available_parallelism.div_ceil(num_threads).max(1)
}

pub struct SessionPool {
    sessions: Mutex<Vec<Session>>,
    available: Condvar,
    created: AtomicUsize,
    capacity: usize,
    model_path: PathBuf,
    build_config: ModelConfig,
}

impl SessionPool {
    pub fn new(initial: Session, model_path: PathBuf, build_config: ModelConfig) -> Self {
        let capacity = pool_capacity(build_config.num_threads);
        Self {
            sessions: Mutex::new(vec![initial]),
            available: Condvar::new(),
            created: AtomicUsize::new(1),
            capacity,
            model_path,
            build_config,
        }
    }

    pub fn acquire(&self) -> Result<PooledSession<'_>> {
        if let Some(session) = self.take_available_session() {
            return Ok(PooledSession { pool: self, session: Some(session) });
        }

        if let Some(session) = self.try_grow()? {
            return Ok(PooledSession { pool: self, session: Some(session) });
        }

        let session = self.wait_for_session();
        Ok(PooledSession { pool: self, session: Some(session) })
    }

    fn release(&self, session: Session) {
        self.sessions.lock().unwrap().push(session);
        self.available.notify_one();
    }

    fn take_available_session(&self) -> Option<Session> {
        self.sessions.lock().unwrap().pop()
    }

    fn try_grow(&self) -> Result<Option<Session>> {
        let grew = self.created.fetch_update(
            Ordering::AcqRel,
            Ordering::Acquire,
            |count| (count < self.capacity).then_some(count + 1),
        );
        if grew.is_err() {
            return Ok(None);
        }

        match build_session(&self.model_path, &self.build_config) {
            Ok(session) => Ok(Some(session)),
            Err(error) => {
                self.created.fetch_sub(1, Ordering::AcqRel);
                Err(error)
            }
        }
    }

    fn wait_for_session(&self) -> Session {
        let mut lock = self.sessions.lock().unwrap();
        loop {
            if let Some(session) = lock.pop() {
                return session;
            }
            lock = self.available.wait(lock).unwrap();
        }
    }
}

pub struct PooledSession<'a> {
    pool: &'a SessionPool,
    session: Option<Session>,
}

impl std::ops::Deref for PooledSession<'_> {
    type Target = Session;
    fn deref(&self) -> &Session { self.session.as_ref().unwrap() }
}

impl std::ops::DerefMut for PooledSession<'_> {
    fn deref_mut(&mut self) -> &mut Session { self.session.as_mut().unwrap() }
}

impl Drop for PooledSession<'_> {
    fn drop(&mut self) {
        if let Some(s) = self.session.take() {
            self.pool.release(s);
        }
    }
}

// ---------------------------------------------------------------------------

fn preferred_execution_providers(order_override: Option<&str>) -> Vec<ExecutionProviderDispatch> {
    let order = resolve_provider_order(order_override);

    let mut providers = Vec::new();
    for provider in parse_provider_registrations(order.as_str()) {
        match provider {
            "xnnpack" => {
                providers.push(XNNPACKExecutionProvider::default().build().fail_silently())
            }
            "coreml" => providers.push(CoreMLExecutionProvider::default().build().fail_silently()),
            _ => {}
        }
    }
    providers
}

fn resolve_provider_order(order_override: Option<&str>) -> String {
    let env_order = std::env::var("GTE_EXECUTION_PROVIDERS").ok();
    resolve_provider_order_with_env(order_override, env_order.as_deref())
}

fn resolve_provider_order_with_env(order_override: Option<&str>, env_order: Option<&str>) -> String {
    order_override
        .or(env_order)
        .unwrap_or("cpu")
        .to_ascii_lowercase()
}

fn parse_provider_registrations(order: &str) -> Vec<&str> {
    let mut providers = Vec::new();
    for provider in order.split(',').map(str::trim).filter(|p| !p.is_empty()) {
        match provider {
            "xnnpack" | "coreml" => providers.push(provider),
            "none" | "cpu" => {}
            _ => {}
        }
    }
    providers
}

pub fn run_session(
    session: &mut Session,
    tokenized: &Tokenized,
    config: &ModelConfig,
) -> Result<Array2<f32>> {
    let input_tensors = InputTensors::from_tokenized(tokenized, config.with_attention_mask)?;
    let outputs = session.run(input_tensors.inputs).map_err(|e| GteError::Ort(e.to_string()))?;
    let array = extract_output_tensor(&outputs, config.output_tensor.as_str())?;

    match config.mode {
        ExtractorMode::Token(idx) => {
            let shape = array.shape();
            if shape.len() != 3 || idx >= shape[1] {
                return Err(GteError::Inference(format!(
                    "token extraction index {} out of bounds for output shape {:?}",
                    idx, shape
                )));
            }
            Ok(array.slice(ndarray::s![.., idx, ..]).into_owned())
        }
        ExtractorMode::MeanPool => {
            let ndim = array.ndim();
            let hidden_states = array.into_dimensionality::<ndarray::Ix3>().map_err(|_| {
                GteError::Inference(format!(
                    "mean pooling requires rank-3 output, got rank {}",
                    ndim
                ))
            })?;
            mean_pool(hidden_states.view(), input_tensors.attention_mask)
        }
        ExtractorMode::Raw => array.into_dimensionality::<Ix2>().map_err(|e| GteError::Shape(e.to_string())),
    }
}

#[cfg(test)]
mod tests {
    use super::{
        parse_provider_registrations, pool_capacity_with_parallelism,
        resolve_provider_order_with_env,
    };

    #[test]
    fn parse_provider_registrations_keeps_supported_order() {
        let parsed = parse_provider_registrations("xnnpack,coreml");
        assert_eq!(parsed, vec!["xnnpack", "coreml"]);
    }

    #[test]
    fn parse_provider_registrations_treats_cpu_and_none_as_fallback() {
        assert!(parse_provider_registrations("cpu").is_empty());
        assert!(parse_provider_registrations("none").is_empty());
        assert!(parse_provider_registrations("none,cpu").is_empty());
    }

    #[test]
    fn parse_provider_registrations_ignores_unknowns_and_empties() {
        let parsed = parse_provider_registrations(" ,xnnpak,,xnnpack,unknown,coreml,");
        assert_eq!(parsed, vec!["xnnpack", "coreml"]);
    }

    #[test]
    fn resolve_provider_order_prefers_override() {
        assert_eq!(
            resolve_provider_order_with_env(Some("xnnpack"), Some("coreml")),
            "xnnpack"
        );
        assert_eq!(resolve_provider_order_with_env(Some("CPU"), None), "cpu");
    }

    #[test]
    fn resolve_provider_order_falls_back_to_env_then_cpu_default() {
        assert_eq!(resolve_provider_order_with_env(None, Some("coreml")), "coreml");
        assert_eq!(resolve_provider_order_with_env(None, None), "cpu");
    }

    #[test]
    fn pool_capacity_uses_bounded_parallel_pool_for_auto_thread_mode() {
        assert_eq!(pool_capacity_with_parallelism(0, 1), 1);
        assert_eq!(pool_capacity_with_parallelism(0, 4), 4);
        assert_eq!(pool_capacity_with_parallelism(0, 8), 6);
    }

    #[test]
    fn pool_capacity_scales_with_available_parallelism() {
        assert_eq!(pool_capacity_with_parallelism(1, 8), 8);
        assert_eq!(pool_capacity_with_parallelism(2, 8), 4);
        assert_eq!(pool_capacity_with_parallelism(3, 8), 3);
        assert_eq!(pool_capacity_with_parallelism(8, 4), 1);
    }
}
