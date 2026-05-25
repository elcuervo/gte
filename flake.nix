{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            ruby_3_4
            rustc
            rustfmt
            cargo
            clippy
            cargo-nextest
            cargo-udeps
            git
            jq
            ripgrep
            hyperfine
            pkg-config
            openssl
            llvmPackages.libclang
            clang
          ];

          shellHook = ''
            export LIBCLANG_PATH=${pkgs.llvmPackages.libclang.lib}/lib
            export OPENSSL_DIR=${pkgs.openssl.dev}
            export OPENSSL_LIB_DIR=${pkgs.openssl.out}/lib
            export OPENSSL_INCLUDE_DIR=${pkgs.openssl.dev}/include
          '';
        };
      });
}
