use crate::error::{GteError, Result};
use crate::model_config::{ExtractorMode, ModelConfig};
use crate::pipeline::{extract_output_tensor, InputTensors};
use crate::postprocess::mean_pool;
use crate::tokenizer::Tokenized;
use ndarray::{Array2, ArrayView2, ArrayViewD, Ix2};
use ort::execution_providers::{CoreMLExecutionProvider, ExecutionProviderDispatch, XNNPACKExecutionProvider};
use ort::session::{OutputSelector, RunOptions, Session};
use std::cell::RefCell;
use std::collections::hash_map::Entry;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

// ---------------------------------------------------------------------------
// Thread-local session storage — each OS thread lazily creates its own ONNX
// session the first time it calls into a given pool.  No Mutex, no contention.
// ---------------------------------------------------------------------------

static NEXT_POOL_ID: AtomicUsize = AtomicUsize::new(1);

struct SessionRecipe {
    model_path: PathBuf,
    build_config: ModelConfig,
}

thread_local! {
    static SESSIONS: RefCell<HashMap<usize, Session>> = RefCell::new(HashMap::new());
}

pub struct SessionPool {
    pool_id: usize,
    recipe: SessionRecipe,
}

impl SessionPool {
    pub fn new(initial: Session, model_path: &Path, build_config: &ModelConfig) -> Result<Self> {
        let pool_id = NEXT_POOL_ID.fetch_add(1, Ordering::Relaxed);

        SESSIONS.with(|map| {
            _ = map.borrow_mut().insert(pool_id, initial);
        });

        Ok(Self {
            pool_id,
            recipe: SessionRecipe { model_path: model_path.to_path_buf(), build_config: build_config.clone() },
        })
    }

    pub fn run(&self, tokenized: &Tokenized, config: &ModelConfig) -> Result<Array2<f32>> {
        self.with_session(|session| run_session(session, tokenized, config))
    }

    pub fn with_session<F, R>(&self, f: F) -> Result<R>
    where
        F: FnOnce(&mut Session) -> Result<R>,
    {
        SESSIONS.with(|map| {
            let mut map = map.borrow_mut();
            let session = match map.entry(self.pool_id) {
                Entry::Occupied(e) => e.into_mut(),
                Entry::Vacant(e) => {
                    let session = build_session(&self.recipe.model_path, &self.recipe.build_config)?;
                    e.insert(session)
                }
            };
            f(session)
        })
    }
}

// ---------------------------------------------------------------------------
// Session construction
// ---------------------------------------------------------------------------

pub fn build_session<P: AsRef<Path>>(model_path: P, config: &ModelConfig) -> Result<Session> {
    fn ort_err(e: impl std::fmt::Display) -> GteError {
        GteError::Ort(e.to_string())
    }

    let opt_level = match config.optimization_level {
        0 => ort::session::builder::GraphOptimizationLevel::Disable,
        1 => ort::session::builder::GraphOptimizationLevel::Level1,
        2 => ort::session::builder::GraphOptimizationLevel::Level2,
        _ => ort::session::builder::GraphOptimizationLevel::Level3,
    };

    let mut builder = Session::builder().map_err(ort_err)?.with_optimization_level(opt_level).map_err(ort_err)?;

    let intra_threads = std::env::var("GTE_INTRA_OP_NUM_THREADS")
        .ok()
        .and_then(|v| v.trim().parse::<usize>().ok())
        .unwrap_or_else(|| {
            std::thread::available_parallelism()
                .map(|n| n.get().min(4))
                .unwrap_or(1)
        });
    builder = builder.with_intra_threads(intra_threads).map_err(ort_err)?;

    if let Some(n) = std::env::var("GTE_INTER_OP_NUM_THREADS").ok().and_then(|v| v.trim().parse::<usize>().ok()) {
        builder = builder.with_inter_threads(n).map_err(ort_err)?;
    }

    let providers = preferred_execution_providers(config.execution_providers.as_deref());
    if !providers.is_empty() {
        builder = builder.with_execution_providers(providers).map_err(ort_err)?;
    }

    builder.commit_from_file(model_path).map_err(ort_err)
}

fn preferred_execution_providers(order_override: Option<&str>) -> Vec<ExecutionProviderDispatch> {
    let order = resolve_provider_order(order_override);

    let mut providers = Vec::new();
    for provider in parse_provider_registrations(order.as_str()) {
        match provider {
            "xnnpack" => {
                providers.push(XNNPACKExecutionProvider::default().build().fail_silently());
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
    order_override.or(env_order).unwrap_or("cpu").to_ascii_lowercase()
}

fn parse_provider_registrations(order: &str) -> Vec<&str> {
    let mut providers = Vec::new();
    for provider in order.split(',').map(str::trim).filter(|p| !p.is_empty()) {
        match provider {
            "xnnpack" | "coreml" => providers.push(provider),
            _ => {}
        }
    }
    providers
}

// ---------------------------------------------------------------------------
// Run a single inference
// ---------------------------------------------------------------------------

pub fn run_session(session: &mut Session, tokenized: &Tokenized, config: &ModelConfig) -> Result<Array2<f32>> {
    let input_tensors = InputTensors::from_tokenized(tokenized, config.with_attention_mask)?;
    let run_opts = RunOptions::new()
        .map_err(|e| GteError::Ort(e.to_string()))?
        .with_outputs(OutputSelector::no_default().with(config.output_tensor.as_str()));
    let outputs =
        session.run_with_options(input_tensors.inputs, &run_opts).map_err(|e| GteError::Ort(e.to_string()))?;
    let array = extract_output_tensor(&outputs, config.output_tensor.as_str())?;

    extract_embeddings(array, input_tensors.attention_mask, config)
}

fn extract_embeddings(
    array: ArrayViewD<'_, f32>,
    attention_mask: ArrayView2<'_, i64>,
    config: &ModelConfig,
) -> Result<Array2<f32>> {
    match config.mode {
        ExtractorMode::Token(idx) => {
            let shape = array.shape();
            if shape.len() != 3 || idx >= shape[1] {
                return Err(GteError::Inference(format!(
                    "token extraction index {idx} out of bounds for output shape {shape:?}"
                )));
            }
            Ok(array.slice(ndarray::s![.., idx, ..]).into_owned())
        }
        ExtractorMode::MeanPool => {
            let ndim = array.ndim();
            let hidden_states = array
                .into_dimensionality::<ndarray::Ix3>()
                .map_err(|_| GteError::Inference(format!("mean pooling requires rank-3 output, got rank {ndim}")))?;
            mean_pool(hidden_states, attention_mask)
        }
        ExtractorMode::Raw => {
            array.into_dimensionality::<Ix2>().map(|view| view.to_owned()).map_err(|e| GteError::Shape(e.to_string()))
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::model_config::{ExtractorMode, ModelConfig, PaddingMode};
    use ndarray::{array, ArrayView2};

    use super::{extract_embeddings, parse_provider_registrations, resolve_provider_order_with_env};

    fn test_config(mode: ExtractorMode) -> ModelConfig {
        ModelConfig {
            max_length: 8,
            padding_mode: PaddingMode::BatchLongest,
            output_tensor: "output".to_string(),
            mode,
            with_type_ids: false,
            with_attention_mask: true,
            optimization_level: 3,
            execution_providers: None,
            lowercase_input: false,
            max_input_chars: None,
        }
    }

    fn empty_attention_mask() -> ArrayView2<'static, i64> {
        static EMPTY: [i64; 0] = [];
        ArrayView2::from_shape((0, 0), &EMPTY).unwrap()
    }

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
        assert_eq!(resolve_provider_order_with_env(Some("xnnpack"), Some("coreml")), "xnnpack");
        assert_eq!(resolve_provider_order_with_env(Some("CPU"), None), "cpu");
    }

    #[test]
    fn resolve_provider_order_falls_back_to_env_then_cpu_default() {
        assert_eq!(resolve_provider_order_with_env(None, Some("coreml")), "coreml");
        assert_eq!(resolve_provider_order_with_env(None, None), "cpu");
    }

    #[test]
    fn extract_embeddings_raw_copies_only_final_matrix() {
        let output = array![[1.0f32, 2.0], [3.0, 4.0]];
        let extracted =
            extract_embeddings(output.view().into_dyn(), empty_attention_mask(), &test_config(ExtractorMode::Raw))
                .unwrap();

        assert_eq!(extracted, output);
    }

    #[test]
    fn extract_embeddings_token_selects_without_copying_full_sequence() {
        let output = array![[[1.0f32, 2.0], [3.0, 4.0], [5.0, 6.0]], [[7.0, 8.0], [9.0, 10.0], [11.0, 12.0]]];
        let expected = array![[3.0f32, 4.0], [9.0, 10.0]];
        let extracted =
            extract_embeddings(output.view().into_dyn(), empty_attention_mask(), &test_config(ExtractorMode::Token(1)))
                .unwrap();

        assert_eq!(extracted, expected);
    }

    #[test]
    fn extract_embeddings_mean_pool_uses_output_view_and_attention_mask() {
        let output = array![[[1.0f32, 3.0], [5.0, 7.0], [100.0, 100.0]], [[2.0, 4.0], [6.0, 8.0], [10.0, 12.0]]];
        let attention_mask = array![[1_i64, 1, 0], [0, 1, 1]];
        let expected = array![[3.0f32, 5.0], [8.0, 10.0]];
        let extracted =
            extract_embeddings(output.view().into_dyn(), attention_mask.view(), &test_config(ExtractorMode::MeanPool))
                .unwrap();

        assert_eq!(extracted, expected);
    }
}
