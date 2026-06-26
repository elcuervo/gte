use crate::error::{GteError, Result};
use crate::model_config::{ExtractorMode, ModelConfig};
use crate::pipeline::{extract_output_tensor, InputTensors};
use crate::postprocess::mean_pool;
use crate::tokenizer::Tokenized;
use ndarray::{Array2, ArrayViewD, Ix2};
use ort::execution_providers::{CoreMLExecutionProvider, ExecutionProviderDispatch, XNNPACKExecutionProvider};
use ort::session::{OutputSelector, RunOptions, Session};
use parking_lot::Mutex;
use std::path::Path;
use std::sync::atomic::{AtomicUsize, Ordering};

pub(crate) fn resolve_pool_size() -> usize {
    if let Some(n) =
        std::env::var("GTE_SESSION_POOL_SIZE").ok().and_then(|v| v.trim().parse::<usize>().ok()).filter(|&n| n > 0)
    {
        return n;
    }
    if let Some(n) =
        std::env::var("PUMA_MAX_THREADS").ok().and_then(|v| v.trim().parse::<usize>().ok()).filter(|&n| n > 0)
    {
        return n.min(8);
    }
    1
}

pub struct SessionPool {
    sessions: Vec<Mutex<Session>>,
    next_idx: AtomicUsize,
}

impl SessionPool {
    pub fn new(model_path: &Path, config: &ModelConfig, pool_size: usize) -> Result<Self> {
        let sessions = (0..pool_size)
            .map(|_| build_session(model_path, config))
            .collect::<Result<Vec<_>>>()?
            .into_iter()
            .map(Mutex::new)
            .collect();
        Ok(Self { sessions, next_idx: AtomicUsize::new(0) })
    }

    pub fn with_session<F, R>(&self, f: F) -> Result<R>
    where
        F: FnOnce(&mut Session) -> Result<R>,
    {
        let idx = if self.sessions.len() == 1 {
            0
        } else {
            self.next_idx.fetch_add(1, Ordering::Relaxed) % self.sessions.len()
        };
        let mut session = self.sessions[idx].lock();
        f(&mut session)
    }

    pub fn len(&self) -> usize {
        self.sessions.len()
    }
}

pub(crate) fn build_session<P: AsRef<Path>>(model_path: P, config: &ModelConfig) -> Result<Session> {
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
        .unwrap_or_else(|| std::thread::available_parallelism().map(|n| n.get().min(4)).unwrap_or(1));
    builder = builder.with_intra_threads(intra_threads).map_err(ort_err)?;

    let inter_threads =
        std::env::var("GTE_INTER_OP_NUM_THREADS").ok().and_then(|v| v.trim().parse::<usize>().ok()).unwrap_or(1);
    builder = builder.with_inter_threads(inter_threads).map_err(ort_err)?;

    let providers = match config.execution_providers.as_deref() {
        Some(override_val) => preferred_execution_providers(Some(override_val)),
        None => auto_detect_providers(),
    };
    if !providers.is_empty() {
        builder = builder.with_execution_providers(providers).map_err(ort_err)?;
    }

    builder.commit_from_file(model_path).map_err(ort_err)
}

fn auto_detect_providers() -> Vec<ExecutionProviderDispatch> {
    #[cfg(target_arch = "aarch64")]
    {
        vec![XNNPACKExecutionProvider::default().build().fail_silently()]
    }
    #[cfg(not(target_arch = "aarch64"))]
    {
        Vec::new()
    }
}

fn preferred_execution_providers(order_override: Option<&str>) -> Vec<ExecutionProviderDispatch> {
    let order = match order_override {
        Some(s) => s.to_ascii_lowercase(),
        None => return auto_detect_providers(),
    };

    if order.is_empty() || order == "cpu" || order == "none" {
        return Vec::new();
    }

    let providers: Vec<_> = order
        .split(',')
        .map(str::trim)
        .filter(|p| !p.is_empty())
        .filter_map(|provider| match provider {
            "xnnpack" => Some(XNNPACKExecutionProvider::default().build().fail_silently()),
            "coreml" => Some(CoreMLExecutionProvider::default().build().fail_silently()),
            _ => None,
        })
        .collect();
    providers
}

pub(crate) fn run_session(session: &mut Session, tokenized: &Tokenized, config: &ModelConfig) -> Result<Array2<f32>> {
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
    attention_mask: ndarray::ArrayView2<'_, i64>,
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

    use super::extract_embeddings;

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
        }
    }

    fn empty_attention_mask() -> ArrayView2<'static, i64> {
        static EMPTY: [i64; 0] = [];
        ArrayView2::from_shape((0, 0), &EMPTY).unwrap()
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

    #[test]
    fn resolve_pool_size_uses_env_var() {
        std::env::set_var("GTE_SESSION_POOL_SIZE", "16");
        let size = super::resolve_pool_size();
        assert_eq!(size, 16);
        std::env::remove_var("GTE_SESSION_POOL_SIZE");
    }
}
