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
    package = inputs.nix-openclaw.packages.${pkgs.stdenv.hostPlatform.system}.openclaw-gateway;
    inherit port;

    # Empty config — the real config is in the agenix secret.
    # This still writes an innocuous {} to /etc/openclaw/openclaw.json
    # which the gateway ignores because OPENCLAW_CONFIG_PATH points elsewhere.
    config = {};

    # Point the gateway at the writable copy
    environment = {
      OPENCLAW_CONFIG_PATH = "/var/lib/openclaw/openclaw.json";
      # Configure npm to use writable directory for plugins
      NPM_CONFIG_PREFIX = "/var/lib/openclaw/.npm-global";
      # Ensure Node.js can find the installed plugins
      NODE_PATH = "/var/lib/openclaw/.npm-global/lib/node_modules";
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

    # Install Matrix plugin at runtime (avoids Nix sandbox network restrictions)
    ExecStartPre = [
      # Copy config (from services.openclaw-gateway.execStartPre)
      "+${pkgs.coreutils}/bin/cp -f ${config.age.secrets."openclaw-config".path} /var/lib/openclaw/openclaw.json"
      "+${pkgs.coreutils}/bin/chown openclaw:openclaw /var/lib/openclaw/openclaw.json"
      "+${pkgs.coreutils}/bin/chmod 0600 /var/lib/openclaw/openclaw.json"
      # Install Matrix plugin
      ''
        ${pkgs.bash}/bin/bash -c '
          export NPM_CONFIG_PREFIX=/var/lib/openclaw/.npm-global
          export PATH=/var/lib/openclaw/.npm-global/bin:$PATH
          export NODE_PATH=/var/lib/openclaw/.npm-global/lib/node_modules
          if [ ! -d /var/lib/openclaw/.npm-global/lib/node_modules/@openclaw/matrix ]; then
            echo "Installing @openclaw/matrix plugin..."
            ${config.services.openclaw-gateway.package}/bin/openclaw plugins install @openclaw/matrix
          else
            echo "@openclaw/matrix plugin already installed"
          fi
        '
      ''
    ];

    # Filesystem
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    # PrivateDevices blocks network interface enumeration - disabled for now
    # PrivateDevices = true;
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
    # TODO: Re-enable syscall filtering with a proper allow-list after identifying
    # all required syscalls for Node.js + Matrix SDK. The Matrix SDK's crypto store
    # needs fchown/fchownat and potentially other syscalls in the @privileged set.
    # Consider using tools like strace to build a complete allow-list or explore
    # alternative sandboxing approaches (e.g., systemd-analyze security, firejail).
    # SystemCallArchitectures = "native";
    # SystemCallFilter = ["@system-service" "@resources" "fchown" "fchownat" "~@privileged" "~@obsolete"];

    # Network — only IPv4/IPv6/Unix (outbound HTTPS to Matrix + Anthropic)
    # AF_NETLINK is needed for network interface enumeration
    RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK"];
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
