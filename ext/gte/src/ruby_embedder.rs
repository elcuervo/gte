#![cfg(feature = "ruby-ffi")]

use std::os::raw::c_void;
use std::sync::Arc;
use magnus::{function, method, prelude::*, wrap, Error, RArray, Ruby};
use crate::embedder::{Embedder, normalize_l2};
use crate::model_config::ModelConfig;
use crate::tokenizer::Tokenized;
use crate::error::GteError;

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

unsafe extern "C" fn run_without_gvl(ptr: *mut c_void) -> *mut c_void {
    // NEVER call Ruby API here — no GVL held.
    let args = &mut *(ptr as *mut InferArgs);
    args.result = Some((*args.embedder).run(&*args.tokenized));
    std::ptr::null_mut()
}

impl RbEmbedder {
    pub fn rb_new(
        ruby: &Ruby,
        tokenizer_path: String,
        model_path: String,
        config_name: String,
    ) -> Result<Self, Error> {
        let config = match config_name.as_str() {
            "e5"      => ModelConfig::e5(),
            "clip"    => ModelConfig::clip(),
            "siglip2" => ModelConfig::siglip2(),
            other => return Err(Error::new(
                ruby.exception_arg_error(),
                format!("unknown config '{}': expected 'e5', 'clip', or 'siglip2'", other),
            )),
        };
        let embedder = Embedder::new(tokenizer_path, model_path, config)
            .map_err(magnus::Error::from)?;
        Ok(RbEmbedder { inner: Arc::new(embedder) })
    }

    pub fn rb_embed(ruby: &Ruby, rb_self: &Self, texts: RArray) -> Result<RArray, Error> {
        let texts: Vec<String> = texts.to_vec()?;

        // Tokenize within GVL — tokenizer internals may not be Send (D-01)
        let tokenized = rb_self.inner.tokenize(&texts).map_err(magnus::Error::from)?;

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
                None,          // ubf: no cancellation — inference is milliseconds
                std::ptr::null_mut(),
            );
            args.result.unwrap().map_err(magnus::Error::from)?
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
