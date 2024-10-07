{
  pkgs,
  rustPlatform,
  ...
}: let
  pname = "nextjs-cache-relay";
  version = "0.1.0";
in
  rustPlatform.buildRustPackage {
    inherit pname version;

    src = pkgs.lib.cleanSourceWith {
      filter = name: type: let
        baseName = baseNameOf (toString name);
      in
        ! (pkgs.lib.hasSuffix ".nix" baseName);
      src = pkgs.lib.cleanSource ../.;
    };

    buildFeatures = [];

    cargoLock = {
      lockFile = ../Cargo.lock;
    };

    nativeBuildInputs = with pkgs; [
      openssh
      pkg-config
    ];

    buildInputs = with pkgs; [
      openssl
    ];

    doCheck = false;
  }


