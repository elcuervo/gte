fn main() {
    let version = std::fs::read_to_string("../../VERSION")
        .expect("VERSION file not found")
        .trim()
        .to_string();

    let cargo_version = env!("CARGO_PKG_VERSION");

    assert_eq!(
        version, cargo_version,
        "VERSION file ({}) doesn't match Cargo.toml ({}). Update Cargo.toml to match.",
        version, cargo_version
    );

    println!("cargo:rerun-if-changed=../../VERSION");
}
