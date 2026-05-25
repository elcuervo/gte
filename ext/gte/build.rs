fn main() {
    let version = std::fs::read_to_string("../../VERSION").expect("VERSION file not found").trim().to_string();

    let cargo_version = env!("CARGO_PKG_VERSION");

    assert_eq!(
        version, cargo_version,
        "VERSION file ({version}) doesn't match Cargo.toml ({cargo_version}). Update Cargo.toml to match.",
    );

    println!("cargo:rerun-if-changed=../../VERSION");

    // Ensure the ORT shared library can be found at runtime via @rpath on macOS.
    // ORT_LIB_LOCATION is set by the Nix dev shell when ORT_STRATEGY=system.
    if let Ok(ort_lib) = std::env::var("ORT_LIB_LOCATION") {
        let lib_dir = std::path::Path::new(&ort_lib).join("lib");
        if lib_dir.exists() {
            println!("cargo:rustc-link-arg=-Wl,-rpath,{}", lib_dir.display());
        }
    }
}
