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
            git
            onnxruntime
            pkg-config
          ];

          shellHook = ''
            export ORT_STRATEGY=system
            export ORT_LIB_LOCATION=${pkgs.onnxruntime}
          '';
        };
      });
}
