{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    rust-overlay,
  } @ inputs: {
    nixosModules= {
      default = import ./nix/module.nix inputs;
    };
  } // flake-utils.lib.eachDefaultSystem (system:
    let
      overlays = [
        (import rust-overlay)
      ];
      pkgs = import nixpkgs {
        inherit system overlays;
      };
      rustToolchain = ./rust-toolchain.toml;
      libPath = pkgs.lib.makeLibraryPath [ pkgs.openssl ];
      rust = (pkgs.rust-bin.fromRustupToolchainFile rustToolchain);

      rustPlatform = pkgs.makeRustPlatform {
        cargo = rust;
        rustc = rust;
      };

      package = import ./nix/package.nix {
        inherit pkgs rustPlatform;
      };
    in {
      packages = {
        default = package;
        nextjs-cache-relay = package;
      };

      devShells = rec {
        default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            cmake
            pkg-config
            rust
          ];

          buildInputs = with pkgs; [
            openssl
          ];
        };

      };

      formatter = pkgs.alejandra;
    }
  );
}
