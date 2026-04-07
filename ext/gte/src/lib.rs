pub mod embedder;
pub mod error;
pub mod model_config;
pub mod session;
pub mod tokenizer;

// Magnus Ruby FFI entrypoint — only compiled when the "ruby-ffi" feature is active.
// The ruby-ffi feature gates magnus + rb-sys (Ruby C symbols). When running
// `cargo test --no-default-features`, this block is excluded, allowing Rust integration
// tests to link without needing a Ruby runtime present.
#[cfg(feature = "ruby-ffi")]
mod ruby_embedder;

#[cfg(feature = "ruby-ffi")]
use magnus::{prelude::*, Error, Ruby};

#[cfg(feature = "ruby-ffi")]
#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("GTE")?;

    // Define GTE::Error < StandardError
    // Per D-08: use exception_standard_error(), NOT exception_runtime_error()
    // StandardError is the correct base — specifically catchable, not ad-hoc
    module.define_error("Error", ruby.exception_standard_error())?;

    // Phase 3: register GTE::Embedder class and methods
    crate::ruby_embedder::register(ruby)?;

    // Install panic hook to prevent undefined behavior when Rust panics
    // cross the FFI boundary. In Phase 1 there are no user-callable Rust methods,
    // but the hook must be in place before any code runs.
    // Per D-09 and research pitfall 6.
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
