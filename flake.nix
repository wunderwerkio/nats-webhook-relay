{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    utils.url = "github:wunderwerkio/nix-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    utils,
    rust-overlay,
  } @ inputs: let 
    cargoToml = (builtins.fromTOML (builtins.readFile ./Cargo.toml));
  in({
    nixosModules= {
      default = import ./nix/module.nix {
        inherit inputs cargoToml;
      };
    };
  } // utils.lib.systems.eachDefault (system:
    let
      overlays = [
        (import rust-overlay)
      ];
      pkgs = import nixpkgs {
        inherit system overlays;
      };
      rustToolchain = ./rust-toolchain.toml;
      rust = (pkgs.rust-bin.fromRustupToolchainFile rustToolchain);

      rustPlatform = pkgs.makeRustPlatform {
        cargo = rust;
        rustc = rust;
      };

      package = import ./nix/package.nix {
        inherit pkgs rustPlatform cargoToml;
      };
    in {
      packages = {
        default = package;
        "${cargoToml.package.name}" = package;
      };

      devShells = {
        default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            pkg-config
            rust
          ];

          buildInputs = with pkgs; [
            openssl
          ] ++ lib.optionals (system == "aarch64-darwin") [
            # Framework dependencies on Apple Silicon.
            darwin.apple_sdk.frameworks.CoreFoundation
            darwin.apple_sdk.frameworks.CoreServices
            darwin.apple_sdk.frameworks.SystemConfiguration
          ];
        };
      };

      formatter = pkgs.alejandra;
    }
  ));
}
