{
  config,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.server;
  port = 18789;
in {
  # --- Secrets ---
  # Single config file containing the full openclaw JSON config.
  # All Matrix addresses, usernames, room IDs, DM policies etc. stay out of
  # the Nix store and /etc.  The gateway reads it directly from the agenix
  # runtime path via OPENCLAW_CONFIG_PATH override.
  age.secrets."openclaw-config" = {
    rekeyFile = ./openclaw-config.age;
    owner = "openclaw";
    group = "openclaw";
    mode = "0400";
  };

  # Contains: MATRIX_ACCESS_TOKEN, ANTHROPIC_API_KEY, OPENCLAW_GATEWAY_TOKEN
  age.secrets."openclaw-env" = {
    rekeyFile = ./openclaw-env.age;
    owner = "openclaw";
    group = "openclaw";
    mode = "0400";
  };

  # --- Service ---
  services.openclaw-gateway = {
    enable = true;
    package = inputs.nix-openclaw.packages.${pkgs.system}.openclaw-gateway;
    inherit port;

    # Empty config — the real config is in the agenix secret.
    # This still writes an innocuous {} to /etc/openclaw/openclaw.json
    # which the gateway ignores because OPENCLAW_CONFIG_PATH points elsewhere.
    config = {};

    # Point the gateway at the agenix-managed config instead of /etc.
    environment = {
      OPENCLAW_CONFIG_PATH = config.age.secrets."openclaw-config".path;
    };

    environmentFiles = [
      config.age.secrets."openclaw-env".path
    ];
  };

  # --- Systemd hardening ---
  # The openclaw-gateway module provides the base serviceConfig.
  # We extend it with additional hardening directives for a pure chatbot
  # (no tools, no plugins, no shell access).
  systemd.services.openclaw-gateway.serviceConfig = {
    # Logging - override upstream file logging to use journald
    StandardOutput = pkgs.lib.mkForce "journal";
    StandardError = pkgs.lib.mkForce "journal";

    # Filesystem
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ReadWritePaths = ["/var/lib/openclaw"];
    UMask = "0077";

    # Kernel
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectHostname = true;
    ProtectClock = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";

    # Capabilities & privileges
    NoNewPrivileges = true;
    CapabilityBoundingSet = "";
    LockPersonality = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    RemoveIPC = true;

    # Syscall filtering
    SystemCallArchitectures = "native";
    SystemCallFilter = ["@system-service" "~@privileged" "~@resources"];

    # Network — only IPv4/IPv6/Unix (outbound HTTPS to Matrix + Anthropic)
    RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
    RestrictNamespaces = true;

    # Note: MemoryDenyWriteExecute=true breaks Node.js V8 JIT
  };

  # --- Reverse proxy ---
  services.nginx.virtualHosts."openclaw.${cfg.domain}" = {
    forceSSL = true;
    useACMEHost = cfg.domain;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      recommendedProxySettings = true;
      proxyWebsockets = true;
    };
  };

  services.nginx.tailscaleAuth.virtualHosts = [
    "openclaw.${cfg.domain}"
  ];
}
