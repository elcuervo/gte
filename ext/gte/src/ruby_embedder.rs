#![cfg(feature = "ruby-ffi")]

use crate::embedder::{normalize_l2, Embedder};
use crate::error::GteError;
use crate::tokenizer::Tokenized;
use magnus::{function, method, prelude::*, wrap, Error, RArray, Ruby};
use std::os::raw::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Arc;

#[wrap(class = "GTE::Embedder", free_immediately, size)]
pub struct RbEmbedder {
    inner: Arc<Embedder>,
}

struct InferArgs {
    embedder: *const Embedder,
    tokenized: *const Tokenized,
    result: Option<Result<ndarray::Array2<f32>, GteError>>,
}

// Safety: InferArgs is only used inside rb_thread_call_without_gvl while the
// caller holds references to all pointed-to data. The pointers are valid for
// the duration of the call.
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

unsafe extern "C" fn run_without_gvl(ptr: *mut c_void) -> *mut c_void {
    // NEVER call Ruby API here — no GVL held.
    let args = &mut *(ptr as *mut InferArgs);
    let run_result = catch_unwind(AssertUnwindSafe(|| (*args.embedder).run(&*args.tokenized)));
    args.result = Some(match run_result {
        Ok(result) => result,
        Err(payload) => Err(GteError::Inference(format!(
            "panic during inference: {}",
            panic_payload_to_string(payload),
        ))),
    });
    std::ptr::null_mut()
}

impl RbEmbedder {
    pub fn rb_new(
        _ruby: &Ruby,
        dir_path: String,
        num_threads: usize,
        optimization_level: u8,
    ) -> Result<Self, Error> {
        let embedder = Embedder::from_dir(dir_path, num_threads, optimization_level)
            .map_err(magnus::Error::from)?;
        Ok(RbEmbedder {
            inner: Arc::new(embedder),
        })
    }

    pub fn rb_embed(ruby: &Ruby, rb_self: &Self, texts: RArray) -> Result<RArray, Error> {
        let texts: Vec<String> = texts.to_vec()?;

        // Tokenize within GVL — tokenizer internals may not be Send (D-01)
        let tokenized = rb_self
            .inner
            .tokenize(&texts)
            .map_err(magnus::Error::from)?;

        // Release GVL for ORT inference only (D-02, D-03)
        let embeddings = unsafe {
            let mut args = InferArgs {
                embedder: Arc::as_ptr(&rb_self.inner),
                tokenized: &tokenized as *const Tokenized,
                result: None,
            };
            rb_sys::rb_thread_call_without_gvl(
                Some(run_without_gvl),
                &mut args as *mut InferArgs as *mut c_void,
                None, // ubf: no cancellation — inference is milliseconds
                std::ptr::null_mut(),
            );
            let result = args.result.take().ok_or_else(|| {
                magnus::Error::from(GteError::Inference(
                    "inference did not return a result".to_string(),
                ))
            })?;
            result.map_err(magnus::Error::from)?
        };

        // L2 normalize (D-08) then convert to Ruby Array<Array<Float>>
        let normalized = normalize_l2(embeddings);
        array2_to_rarray(ruby, normalized)
    }
}

fn array2_to_rarray(ruby: &Ruby, arr: ndarray::Array2<f32>) -> Result<RArray, Error> {
    let outer = ruby.ary_new_capa(arr.nrows());
    for row in arr.rows() {
        let inner = ruby.ary_new_capa(row.len());
        for &val in row.iter() {
            inner.push(val)?;
        }
        outer.push(inner)?;
    }
    Ok(outer)
}

pub fn register(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("GTE")?;
    let class = module.define_class("Embedder", ruby.class_object())?;
    class.define_singleton_method("new", function!(RbEmbedder::rb_new, 3))?;
    class.define_method("embed", method!(RbEmbedder::rb_embed, 1))?;
    Ok(())
}
