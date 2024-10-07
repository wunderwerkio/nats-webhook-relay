inputs: {
  lib,
  pkgs,
  config,
  ...
}: with lib; let
  cfg = config.services.nextjs-cache-relay;
  inherit (pkgs.stdenv.hostPlatform) system;
in {
  options.services.nextjs-cache-relay = {
    enable = mkEnableOption (mdDoc "Next.js Cache Relay");

    package = mkPackageOptionMD inputs.self.packages.${system} "nextjs-cache-relay" {};

    user = mkOption {
      default = "nextcacherelay";
      type = types.str;
    };

    group = mkOption {
      default = "nextcacherelay";
      type = types.str;
    };

    webhookDestination = mkOption {
      type = types.str;
    };

    natsHost = mkOption {
      type = types.str;
    };

    natsUser = mkOption {
      type = types.str;
    };

    natsPassword = mkOption {
      type = types.str;
    };

    log = mkOption {
      type = types.str;
      default = "info";
    };
  };

  config = mkIf cfg.enable {
    systemd.packages = [ cfg.package ];
    systemd.services."nextjs-cache-relay" = {
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        WEBHOOK_DESTINATION = cfg.webhookDestination;
        NATS_HOST = cfg.natsHost;
        NATS_USER = cfg.natsUser;
        NATS_PASS = cfg.natsPassword;
        RUST_LOG = cfg.log;
      };

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/nextjs-cache-relay";
        User = cfg.user;
        Group = cfg.group;
        Restart = "on-failure";
        RestartSec = "5s";
        RuntimeDirectory = "nextjs-cache-relay";
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

    users.users = optionalAttrs (cfg.user == "nextcacherelay") {
      "nextcacherelay" = {
        isSystemUser = true;
        group = cfg.group;
      };
    };

    users.groups = optionalAttrs (cfg.group == "nextcacherelay") {
      "nextcacherelay" = {};
    };
  };
}

