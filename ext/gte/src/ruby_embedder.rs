#![cfg(feature = "ruby-ffi")]

use crate::embedder::{normalize_l2, Embedder};
use crate::error::GteError;
use magnus::{function, method, prelude::*, wrap, Error, RArray, Ruby};
use std::os::raw::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Arc;

#[wrap(class = "GTE::Embedder", free_immediately, size)]
pub struct RbEmbedder {
    inner: Arc<Embedder>,
}

#[wrap(class = "GTE::Tensor", free_immediately, size)]
pub struct RbTensor {
    rows: usize,
    cols: usize,
    data: Vec<f32>,
}

struct InferArgs {
    embedder: *const Embedder,
    texts: *const Vec<String>,
    result: Option<Result<ndarray::Array2<f32>, GteError>>,
}

unsafe impl Send for InferArgs {}

fn panic_payload_to_string(payload: Box<dyn std::any::Any + Send>) -> String {
    if let Some(msg) = payload.downcast_ref::<&str>() {
        (*msg).to_string()
    } else if let Some(msg) = payload.downcast_ref::<String>() {
        msg.clone()
    } else {
        "unknown panic payload".to_string()
    }
}

fn infer_without_gvl(embedder: &Arc<Embedder>, texts: Vec<String>) -> Result<ndarray::Array2<f32>, Error> {
    let embeddings = unsafe {
        let mut args = InferArgs {
            embedder: Arc::as_ptr(embedder),
            texts: &texts as *const Vec<String>,
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

unsafe extern "C" fn run_without_gvl(ptr: *mut c_void) -> *mut c_void {
    let args = &mut *(ptr as *mut InferArgs);
    let run_result = catch_unwind(AssertUnwindSafe(|| {
        let tokenized = (*args.embedder).tokenize(&*args.texts)?;
        let embeddings = (*args.embedder).run(&tokenized)?;
        Ok(normalize_l2(embeddings))
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
    ) -> Result<Self, Error> {
        let name = if model_name.is_empty() {
            None
        } else {
            Some(model_name.as_str())
        };
        let embedder = Embedder::from_dir(&dir_path, num_threads, optimization_level, name)
            .map_err(magnus::Error::from)?;
        Ok(RbEmbedder {
            inner: Arc::new(embedder),
        })
    }

    pub fn rb_embed(_ruby: &Ruby, rb_self: &Self, texts: RArray) -> Result<RbTensor, Error> {
        let texts: Vec<String> = texts.to_vec()?;
        let embeddings = infer_without_gvl(&rb_self.inner, texts)?;
        tensor_from_array(embeddings)
    }

    pub fn rb_embed_one(_ruby: &Ruby, rb_self: &Self, text: String) -> Result<RbTensor, Error> {
        let embeddings = infer_without_gvl(&rb_self.inner, vec![text])?;
        tensor_from_array(embeddings)
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
    embedder_class.define_singleton_method("new", function!(RbEmbedder::rb_new, 4))?;
    embedder_class.define_method("embed", method!(RbEmbedder::rb_embed, 1))?;
    embedder_class.define_method("embed_one", method!(RbEmbedder::rb_embed_one, 1))?;

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
