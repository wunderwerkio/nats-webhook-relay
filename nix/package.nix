{
  pkgs,
  rustPlatform,
  cargoToml,
  ...
}: let
  pname = cargoToml.package.name;
  version = cargoToml.package.version;
in
  # Build rust package.
  rustPlatform.buildRustPackage {
    inherit pname version;

    # Add project files, excluding .nix files.
    src = pkgs.lib.cleanSourceWith {
      filter = name: type: let
        baseName = baseNameOf (toString name);
      in
        ! (pkgs.lib.hasSuffix ".nix" baseName);
      src = pkgs.lib.cleanSource ../.;
    };

    # No feature flags needed.
    buildFeatures = [];

    # Read in Cargo.lock for dependencies.
    cargoLock = {
      lockFile = ../Cargo.lock;
    };

    nativeBuildInputs = with pkgs; [
      pkg-config
    ];

    buildInputs = with pkgs; [
      # Needed for reqwest.
      openssl
    ] ++ lib.optionals (system == "aarch64-darwin") [
      # Framework dependencies on Apple Silicon.
      darwin.apple_sdk.frameworks.CoreFoundation
      darwin.apple_sdk.frameworks.CoreServices
      darwin.apple_sdk.frameworks.SystemConfiguration
    ];

    doCheck = true;
  }


