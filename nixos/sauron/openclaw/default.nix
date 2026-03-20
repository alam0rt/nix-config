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

    # Public/non-secret configuration
    # Secrets (API keys, tokens, Matrix credentials) stay in agenix
    config = {
      gateway = {
        mode = "local";
        bind = "loopback"; # listen on 127.0.0.1 so nginx can proxy locally
        auth = {
          mode = "trusted-proxy"; # none | token | password | trusted-proxy 
          trustedProxy = {
            userHeader = "x-webauth-user";
          };
        };
        controlUi = {
          allowedOrigins = [
            "https://openclaw.${cfg.domain}"
          ];
        };
        trustedProxies = [
          "127.0.0.1" # nginx runs on loopback; only source that will ever connect
        ];
      };
      channels = {
        matrix = {
          dm = {
            policy = "open";
            allowFrom = ["*"];
          };
        };
      };
      agents = {
        defaults = {
          workspace = "/var/lib/openclaw/workspace";
          model = {
            primary = "openrouter/nvidia/nemotron-3-super-120b-a12b:free";
          };
          models = {
            "openrouter/nvidia/nemotron-3-super-120b-a12b:free" = {
              alias = "nemotron";
            };
          };
          memorySearch = {
            provider = "openai";
            model = "embeddinggemma-300m";
            fallback = "none";
            remote = {
              baseUrl = "http://127.0.0.1:8001/v1/";
              apiKey = "vllm-local";
            };
          };
        };
        list = [
          {
            id = "admin";
            agentDir = "/var/lib/openclaw/agents/admin/agent";
            identity = {
              name = "Mojo";
              theme = "A cute, helpful mini fox terrier with elevated permissions";
              emoji = "🐶"
            };
            tools = {
              profile = "full";
              elevated = {
                enabled = true;
              };
            };
          }
          {
            id = "basic";
            default = true;
            agentDir = "/var/lib/openclaw/agents/basic/agent";
            identity = {
              name = "Mojo";
              theme = "A cute, helpful mini fox terrier";
              emoji = "🐶"
            };
            tools = {
              profile = "messaging";
              elevated = {
                enabled = false;
              };
              deny = [
                "exec" "process" "write" "edit" "apply_patch"
                "browser" "canvas" "cron" "gateway" "nodes"
              ];
            };
          }
        ];
      };
      bindings = [
        {
          agentId = "admin";
          match = {
            channel = "matrix";
            peer = {
              kind = "direct";
              id = "@sammm:chat.samlockart.com";
            };
          };
        }
        {
          agentId = "basic";
          match = {
            channel = "matrix";
          };
        }
      ];
      tools = {
        exec = {
          backgroundMs = 10000;
          timeoutSec = 30;
        };
        elevated = {
          enabled = true;
          allowFrom = {
            matrix = ["@sammm:chat.samlockart.com"];
          };
        };
      };
      messages = {
        ackReaction = "🐶";
        ackReactionScope = "group-mentions";
      };
      session = {
        scope = "per-sender";
        reset = {
          mode = "idle";
          idleMinutes = 240;
        };
        maintenance = {
          mode = "enforce";
          pruneAfter = "30d";
          maxEntries = 500;
        };
      };
    };

    # Point the gateway at the writable copy
    environment = {
      OPENCLAW_CONFIG_PATH = "/var/lib/openclaw/openclaw.json";
      # Configure npm to use writable directory for plugins
      NPM_CONFIG_PREFIX = "/var/lib/openclaw/.npm-global";
      # Ensure Node.js can find the installed plugins and their dependencies
      # Plugin extensions are in /var/lib/openclaw/extensions/<plugin>/node_modules
      NODE_PATH = "/var/lib/openclaw/extensions/matrix/node_modules";
      # Enable vLLM provider auto-discovery (points to llama-cpp on port 8000)
      VLLM_API_KEY = "vllm-local";
    };

    # Tailscale CLI needed for gateway.tailscale.mode = "serve"
    servicePath = [config.services.tailscale.package];

    environmentFiles = [
      config.age.secrets."openclaw-env".path
    ];
  };

  # Allow the openclaw service account to read the system journal
  # Pin the UID so the cgroup slice name is stable across rebuilds
  users.users.openclaw = {
    uid = 976;
    extraGroups = ["systemd-journal"];
  };

  # --- Cgroup resource limits for openclaw ---
  # Mirror the raf user slice to constrain the gateway process
  systemd.slices."user-976" = {
    overrideStrategy = "asDropin";
    # https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html
    sliceConfig = {
      "CPUWeight" = "20";
      "CPUQuota" = "3200%"; # out of 6400%
      "MemoryHigh" = "32G";
      "MemoryMax" = "40G";
      "TasksMax" = "2048";
      "IOWeight" = "20";
    };
  };

  # --- Systemd ordering ---
  # Ensure openclaw-gateway starts after llama-cpp is ready, so vLLM provider
  # discovery succeeds on first attempt rather than falling back to openrouter.
  systemd.services.openclaw-gateway.after = ["llama-cpp.service"];
  systemd.services.openclaw-gateway.wants = ["llama-cpp.service"];

  # --- Systemd hardening ---
  # The openclaw-gateway module provides the base serviceConfig.
  # We extend it as a second layer of defense. The admin agent has full tool
  # access (exec, elevated); the basic agent is restricted to messaging only
  # at the OpenClaw config level. Systemd guards below limit blast radius.
  systemd.services.openclaw-gateway.serviceConfig = {
    # Logging - override upstream file logging to use journald
    StandardOutput = pkgs.lib.mkForce "journal";
    StandardError = pkgs.lib.mkForce "journal";

    # Install Matrix plugin at runtime (avoids Nix sandbox network restrictions)
    ExecStartPre = let
      mergeConfig = pkgs.writeShellScript "merge-openclaw-config" ''
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' \
          ${pkgs.writeText "openclaw-base-config.json" (builtins.toJSON config.services.openclaw-gateway.config)} \
          ${config.age.secrets."openclaw-config".path} \
          > /var/lib/openclaw/openclaw.json
      '';
      installPlugin = pkgs.writeShellScript "install-matrix-plugin" ''
        export NPM_CONFIG_PREFIX=/var/lib/openclaw/.npm-global
        export PATH=/var/lib/openclaw/.npm-global/bin:${pkgs.nodejs_22}/bin:${pkgs.python3}/bin:$PATH
        export NODE_PATH=/var/lib/openclaw/.npm-global/lib/node_modules
        if [ ! -d /var/lib/openclaw/extensions/matrix ]; then
          echo "Installing @openclaw/matrix plugin..."
          ${config.services.openclaw-gateway.package}/bin/openclaw plugins install @openclaw/matrix
        else
          echo "@openclaw/matrix plugin already installed"
        fi
      '';
      installSkills = pkgs.writeShellScript "install-openclaw-skills" ''
        export NPM_CONFIG_PREFIX=/var/lib/openclaw/.npm-global
        export PATH=/var/lib/openclaw/.npm-global/bin:${pkgs.nodejs_22}/bin:${pkgs.python3}/bin:$PATH
        export NODE_PATH=/var/lib/openclaw/.npm-global/lib/node_modules
        echo "Installing self-improving-agent skill..."
        ${config.services.openclaw-gateway.package}/bin/openclaw skills install pskoett/self-improving-agent || true
      '';
      ensureAgentDirs = pkgs.writeShellScript "ensure-openclaw-agent-dirs" ''
        for dir in /var/lib/openclaw/agents/admin/agent \
                   /var/lib/openclaw/agents/basic/agent \
                   /var/lib/openclaw/workspace; do
          ${pkgs.coreutils}/bin/mkdir -p "$dir"
        done
      '';
    in [
      # Merge base config with secrets using jq
      "${mergeConfig}"
      "+${pkgs.coreutils}/bin/chown openclaw:openclaw /var/lib/openclaw/openclaw.json"
      "+${pkgs.coreutils}/bin/chmod 0600 /var/lib/openclaw/openclaw.json"
      # Create per-agent directories and shared workspace
      "${ensureAgentDirs}"
      # Install Matrix plugin
      "${installPlugin}"
      # Install skills
      "${installSkills}"
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
      # Note: do NOT set recommendedProxySettings = true here — it sets
      # proxy_set_header Connection "" which kills WebSocket upgrades.
      # The global recommendedProxySettings handles common headers already.
      proxyWebsockets = true;
    };
  };

  services.nginx.tailscaleAuth.virtualHosts = [
    "openclaw.${cfg.domain}"
  ];
}
