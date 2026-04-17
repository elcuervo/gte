#![cfg(feature = "ruby-ffi")]

use crate::embedder::{normalize_l2, Embedder};
use crate::error::GteError;
use crate::model_config::ModelLoadOverrides;
use crate::reranker::Reranker;
use magnus::{function, method, prelude::*, wrap, Error, RArray, Ruby};
use std::os::raw::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Arc;

#[wrap(class = "GTE::Embedder", free_immediately, size)]
pub struct RbEmbedder {
    inner: Arc<Embedder>,
    normalize: bool,
}

#[wrap(class = "GTE::Reranker", free_immediately, size)]
pub struct RbReranker {
    inner: Arc<Reranker>,
    sigmoid: bool,
}

#[wrap(class = "GTE::Tensor", free_immediately, size)]
pub struct RbTensor {
    rows: usize,
    cols: usize,
    data: Vec<f32>,
}

// ---------------------------------------------------------------------------
// GVL-release helpers
// ---------------------------------------------------------------------------

struct InferArgs {
    embedder: *const Embedder,
    texts: *const Vec<String>,
    normalize: bool,
    result: Option<crate::error::Result<ndarray::Array2<f32>>>,
}

unsafe impl Send for InferArgs {}

struct ScoreArgs {
    reranker: *const Reranker,
    pairs: *const Vec<(String, String)>,
    apply_sigmoid: bool,
    result: Option<crate::error::Result<Vec<f32>>>,
}

unsafe impl Send for ScoreArgs {}

fn panic_payload_to_string(payload: Box<dyn std::any::Any + Send>) -> String {
    if let Some(msg) = payload.downcast_ref::<&str>() {
        (*msg).to_string()
    } else if let Some(msg) = payload.downcast_ref::<String>() {
        msg.clone()
    } else {
        "unknown panic payload".to_string()
    }
}

unsafe extern "C" fn run_without_gvl(ptr: *mut c_void) -> *mut c_void {
    let args = &mut *(ptr as *mut InferArgs);
    let run_result = catch_unwind(AssertUnwindSafe(|| {
        let tokenized = (*args.embedder).tokenize(&*args.texts)?;
        let embeddings = (*args.embedder).run(&tokenized)?;
        if args.normalize { Ok(normalize_l2(embeddings)) } else { Ok(embeddings) }
    }));
    args.result = Some(match run_result {
        Ok(result) => result,
        Err(payload) => Err(GteError::Inference(format!(
            "panic during inference: {}",
            panic_payload_to_string(payload),
        ))),
    });
    std::ptr::null_mut()
}

unsafe extern "C" fn run_score_without_gvl(ptr: *mut c_void) -> *mut c_void {
    let args = &mut *(ptr as *mut ScoreArgs);
    let run_result = catch_unwind(AssertUnwindSafe(|| {
        (*args.reranker).score_pairs(&*args.pairs, args.apply_sigmoid)
    }));
    args.result = Some(match run_result {
        Ok(result) => result,
        Err(payload) => Err(GteError::Inference(format!(
            "panic during reranking: {}",
            panic_payload_to_string(payload),
        ))),
    });
    std::ptr::null_mut()
}

fn infer_without_gvl(
    embedder: &Arc<Embedder>,
    normalize: bool,
    texts: Vec<String>,
) -> Result<ndarray::Array2<f32>, Error> {
    let embeddings = unsafe {
        let mut args = InferArgs {
            embedder: Arc::as_ptr(embedder),
            texts: &texts as *const Vec<String>,
            normalize,
            result: None,
        };
        rb_sys::rb_thread_call_without_gvl(
            Some(run_without_gvl),
            &mut args as *mut InferArgs as *mut c_void,
            None,
            std::ptr::null_mut(),
        );
        let result = args.result.take().ok_or_else(|| {
            magnus::Error::from(GteError::Inference(
                "inference did not return a result".to_string(),
            ))
        })?;
        result.map_err(magnus::Error::from)?
    };
    Ok(embeddings)
}

fn score_without_gvl(
    reranker: &Arc<Reranker>,
    pairs: Vec<(String, String)>,
    apply_sigmoid: bool,
) -> Result<Vec<f32>, Error> {
    let scores = unsafe {
        let mut args = ScoreArgs {
            reranker: Arc::as_ptr(reranker),
            pairs: &pairs as *const Vec<(String, String)>,
            apply_sigmoid,
            result: None,
        };
        rb_sys::rb_thread_call_without_gvl(
            Some(run_score_without_gvl),
            &mut args as *mut ScoreArgs as *mut c_void,
            None,
            std::ptr::null_mut(),
        );
        let result = args.result.take().ok_or_else(|| {
            magnus::Error::from(GteError::Inference(
                "reranking did not return a result".to_string(),
            ))
        })?;
        result.map_err(magnus::Error::from)?
    };
    Ok(scores)
}

// ---------------------------------------------------------------------------

fn tensor_from_array(embeddings: ndarray::Array2<f32>) -> Result<RbTensor, Error> {
    let rows = embeddings.nrows();
    let cols = embeddings.ncols();
    let (data, offset) = embeddings.into_raw_vec_and_offset();
    if let Some(off) = offset.filter(|&o| o != 0) {
        return Err(magnus::Error::from(GteError::Inference(format!(
            "unexpected non-zero tensor offset: {}",
            off
        ))));
    }
    Ok(RbTensor { rows, cols, data })
}

impl RbEmbedder {
    pub fn rb_new(
        _ruby: &Ruby,
        dir_path: String,
        num_threads: usize,
        optimization_level: u8,
        model_name: String,
        normalize: bool,
        output_tensor: String,
        max_length: usize,
        padding: String,
        execution_providers: String,
    ) -> Result<Self, Error> {
        let name = if model_name.is_empty() { None } else { Some(model_name.as_str()) };
        let output_override = if output_tensor.is_empty() { None } else { Some(output_tensor.as_str()) };
        let max_length_override = if max_length == 0 { None } else { Some(max_length) };
        let execution_providers_override = if execution_providers.is_empty() { None } else { Some(execution_providers.as_str()) };
        let padding_override = if padding.is_empty() { None } else { Some(padding.as_str()) };
        let overrides = ModelLoadOverrides {
            model_name: name,
            output_tensor: output_override,
            max_length: max_length_override,
            padding: padding_override,
            execution_providers: execution_providers_override,
        };
        let embedder = Embedder::from_dir(&dir_path, num_threads, optimization_level, overrides)
            .map_err(magnus::Error::from)?;
        Ok(RbEmbedder { inner: Arc::new(embedder), normalize })
    }

    pub fn rb_embed(_ruby: &Ruby, rb_self: &Self, texts: RArray) -> Result<RbTensor, Error> {
        let texts: Vec<String> = texts.to_vec()?;
        let embeddings = infer_without_gvl(&rb_self.inner, rb_self.normalize, texts)?;
        tensor_from_array(embeddings)
    }

    pub fn rb_embed_one(_ruby: &Ruby, rb_self: &Self, text: String) -> Result<RbTensor, Error> {
        let embeddings = infer_without_gvl(&rb_self.inner, rb_self.normalize, vec![text])?;
        tensor_from_array(embeddings)
    }
}

impl RbReranker {
    pub fn rb_new(
        _ruby: &Ruby,
        dir_path: String,
        num_threads: usize,
        optimization_level: u8,
        model_name: String,
        sigmoid: bool,
        output_tensor: String,
        max_length: usize,
        padding: String,
        execution_providers: String,
    ) -> Result<Self, Error> {
        let name = if model_name.is_empty() { None } else { Some(model_name.as_str()) };
        let output_override = if output_tensor.is_empty() { None } else { Some(output_tensor.as_str()) };
        let max_length_override = if max_length == 0 { None } else { Some(max_length) };
        let execution_providers_override = if execution_providers.is_empty() { None } else { Some(execution_providers.as_str()) };
        let padding_override = if padding.is_empty() { None } else { Some(padding.as_str()) };
        let overrides = ModelLoadOverrides {
            model_name: name,
            output_tensor: output_override,
            max_length: max_length_override,
            padding: padding_override,
            execution_providers: execution_providers_override,
        };
        let reranker = Reranker::from_dir(&dir_path, num_threads, optimization_level, overrides)
            .map_err(magnus::Error::from)?;
        Ok(RbReranker { inner: Arc::new(reranker), sigmoid })
    }

    pub fn rb_score(
        ruby: &Ruby,
        rb_self: &Self,
        query: String,
        candidates: RArray,
    ) -> Result<RArray, Error> {
        let candidates: Vec<String> = candidates.to_vec()?;
        let pairs: Vec<(String, String)> = candidates.into_iter().map(|c| (query.clone(), c)).collect();
        let scores = score_without_gvl(&rb_self.inner, pairs, rb_self.sigmoid)?;
        let out = ruby.ary_new_capa(scores.len());
        for score in scores {
            out.push(score)?;
        }
        Ok(out)
    }
}

impl RbTensor {
    pub fn len(&self) -> usize {
        self.rows
    }

    pub fn rows(&self) -> usize {
        self.rows
    }

    pub fn dim(&self) -> usize {
        self.cols
    }

    pub fn shape(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
        let out = ruby.ary_new_capa(2);
        out.push(rb_self.rows)?;
        out.push(rb_self.cols)?;
        Ok(out)
    }

    pub fn row(ruby: &Ruby, rb_self: &Self, index: usize) -> Result<RArray, Error> {
        if index >= rb_self.rows {
            return Err(magnus::Error::from(GteError::Inference(format!(
                "row index {} out of bounds for {} rows",
                index, rb_self.rows
            ))));
        }
        let start = index * rb_self.cols;
        let end = start + rb_self.cols;
        let out = ruby.ary_new_capa(rb_self.cols);
        for &value in &rb_self.data[start..end] {
            out.push(value)?;
        }
        Ok(out)
    }

    pub fn first(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
        Self::row(ruby, rb_self, 0)
    }

    pub fn row_binary_f32(
        ruby: &Ruby,
        rb_self: &Self,
        index: usize,
    ) -> Result<magnus::RString, Error> {
        if index >= rb_self.rows {
            return Err(magnus::Error::from(GteError::Inference(format!(
                "row index {} out of bounds for {} rows",
                index, rb_self.rows
            ))));
        }
        let start = index * rb_self.cols;
        let end = start + rb_self.cols;
        let bytes = unsafe {
            std::slice::from_raw_parts(
                rb_self.data[start..end].as_ptr() as *const u8,
                rb_self.cols * std::mem::size_of::<f32>(),
            )
        };
        Ok(ruby.str_from_slice(bytes))
    }

    pub fn to_a(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
        let outer = ruby.ary_new_capa(rb_self.rows);
        for row_idx in 0..rb_self.rows {
            outer.push(Self::row(ruby, rb_self, row_idx)?)?;
        }
        Ok(outer)
    }

    pub fn to_binary_f32(ruby: &Ruby, rb_self: &Self) -> Result<magnus::RString, Error> {
        let bytes = unsafe {
            std::slice::from_raw_parts(
                rb_self.data.as_ptr() as *const u8,
                rb_self.data.len() * std::mem::size_of::<f32>(),
            )
        };
        Ok(ruby.str_from_slice(bytes))
    }
}

pub fn register(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("GTE")?;
    let embedder_class = module.define_class("Embedder", ruby.class_object())?;
    embedder_class.define_singleton_method("new", function!(RbEmbedder::rb_new, 9))?;
    embedder_class.define_method("embed", method!(RbEmbedder::rb_embed, 1))?;
    embedder_class.define_method("embed_one", method!(RbEmbedder::rb_embed_one, 1))?;

    let reranker_class = module.define_class("Reranker", ruby.class_object())?;
    reranker_class.define_singleton_method("new", function!(RbReranker::rb_new, 9))?;
    reranker_class.define_method("score", method!(RbReranker::rb_score, 2))?;

    let tensor_class = module.define_class("Tensor", ruby.class_object())?;
    tensor_class.define_method("rows", method!(RbTensor::rows, 0))?;
    tensor_class.define_method("size", method!(RbTensor::len, 0))?;
    tensor_class.define_method("length", method!(RbTensor::len, 0))?;
    tensor_class.define_method("dim", method!(RbTensor::dim, 0))?;
    tensor_class.define_method("shape", method!(RbTensor::shape, 0))?;
    tensor_class.define_method("[]", method!(RbTensor::row, 1))?;
    tensor_class.define_method("row", method!(RbTensor::row, 1))?;
    tensor_class.define_method("first", method!(RbTensor::first, 0))?;
    tensor_class.define_method("row_binary_f32", method!(RbTensor::row_binary_f32, 1))?;
    tensor_class.define_method("to_a", method!(RbTensor::to_a, 0))?;
    tensor_class.define_method("to_binary_f32", method!(RbTensor::to_binary_f32, 0))?;
    Ok(())
}
