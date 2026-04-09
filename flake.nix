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
            git
            jq
            ripgrep
            hyperfine
            onnxruntime
            pkg-config
            llvmPackages.libclang
            clang
          ];

          shellHook = ''
            export LIBCLANG_PATH=${pkgs.llvmPackages.libclang.lib}/lib
            export ORT_STRATEGY=system
            export ORT_LIB_LOCATION=${pkgs.onnxruntime}
            export ORT_DYLIB_PATH=${pkgs.onnxruntime}/lib/libonnxruntime.dylib
            export DYLD_LIBRARY_PATH=${pkgs.onnxruntime}/lib''${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}
          '';
        };
      });
}
