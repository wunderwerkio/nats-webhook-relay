{ inputs, cargoToml }: {
  lib,
  pkgs,
  config,
  ...
}: with lib; let
  cfg = config.services."${cargoToml.package.name}";
  defaultUser = "natswebhookrelay";
  defaultGroup = "natswebhookrelay";

  inherit (pkgs.stdenv.hostPlatform) system;
in {
  # Service configuration. 
  options.services."${cargoToml.package.name}" = {
    enable = mkEnableOption (mdDoc "NATS Webhook Relay");

    package = mkPackageOption inputs.self.packages.${system} cargoToml.package.name {};

    user = mkOption {
      type = types.str;
      default = defaultUser;
    };

    group = mkOption {
      type = types.str;
      default = defaultGroup;
    };

    webhookDestination = mkOption {
      type = types.str;
    };

    natsAddress = mkOption {
      type = types.str;
    };

    natsUser = mkOption {
      type = types.str;
    };

    natsPassword = mkOption {
      type = types.str;
    };

    natsSubjectPrefix = mkOption {
      type = types.str;
    };

    natsRelayedSubjectPrefix = mkOption {
      type = types.str;
    };

    log = mkOption {
      type = types.str;
      default = "info";
    };
  };

  # System config.
  config = mkIf cfg.enable {
    # Add package.
    systemd.packages = [ cfg.package ];

    # Add systemd service.
    systemd.services.${cargoToml.package.name} = {
      # Network is required.
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      # Configure program by env vars.
      environment = {
        WEBHOOK_DESTINATION = cfg.webhookDestination;
        NATS_ADDRESS = cfg.natsAddress;
        NATS_USER = cfg.natsUser;
        NATS_PASS = cfg.natsPassword;
        NATS_SUBJECT_PREFIX = cfg.natsSubjectPrefix;
        NATS_RELAYED_SUBJECT_PREFIX = cfg.natsRelayedSubjectPrefix;
        RUST_LOG = cfg.log;
      };

      # Hardened service config.
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/${cargoToml.package.name}";
        User = cfg.user;
        Group = cfg.group;
        Restart = "on-failure";
        RestartSec = "5s";
        RuntimeDirectory = cargoToml.package.name;
        RuntimeDirectoryMode = "0755";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        PrivateMounts = true;
        # Prevent error: Too many open files (os error 24)
        LimitNOFILE = 16384;
      };
    };

    # Add system user if default is used.
    users.users = optionalAttrs (cfg.user == defaultUser) {
      "${defaultUser}" = {
        isSystemUser = true;
        group = cfg.group;
      };
    };

    # Add system group if default is used.
    users.groups = optionalAttrs (cfg.group == defaultGroup) {
      "${defaultGroup}" = {};
    };
  };
}

