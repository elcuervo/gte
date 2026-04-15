pub mod embedder;
pub mod error;
pub mod model_config;
pub mod model_profile;
pub mod pipeline;
pub mod postprocess;
pub mod reranker;
pub mod session;
pub mod tokenizer;

#[cfg(feature = "ruby-ffi")]
mod ruby_embedder;

#[cfg(feature = "ruby-ffi")]
use magnus::{prelude::*, Error, Ruby};

#[cfg(feature = "ruby-ffi")]
#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("GTE")?;
    module.define_error("Error", ruby.exception_standard_error())?;
    crate::ruby_embedder::register(ruby)?;
    std::panic::set_hook(Box::new(|info| {
        let msg = info
            .payload()
            .downcast_ref::<&str>()
            .copied()
            .or_else(|| info.payload().downcast_ref::<String>().map(|s| s.as_str()))
            .unwrap_or("unknown panic");
        eprintln!("GTE Rust panic: {msg}");
    }));

    Ok(())
}
