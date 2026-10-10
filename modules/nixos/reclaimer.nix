# Project Reclaimer dedicated servers (Halo 3 multiplayer on MCC's files).
# https://projectreclaimer.dev/host
#
# Runs the upstream image, ghcr.io/projectreclaimer/project-reclaimer-dedicated,
# with one podman container per server, as upstream's compose.yaml does. The
# servers are Windows programs; the image brings Wine and Xvfb. Upstream calls
# Wine outside the image untested and ships no start script for it, so there
# is no native mode here.
#
# The image holds no game files. Halo 3's files go in `gameDir` (halo3/halo3.dll,
# halo3/maps/*.map and halo3/maps/info/*.mapinfo), copied from your own MCC
# install; until they are there each container logs what is missing and
# re-runs `dedicated check` every 15 seconds.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.reclaimer;

  toml = pkgs.formats.toml {};
  json = pkgs.formats.json {};

  enabledServers = lib.filterAttrs (_: s: s.enable) cfg.servers;

  # `enable` and `extraOptions` are for this module; everything else in a
  # server's attrset is a [[server]] key of dedicated.toml.
  serverToml = s: removeAttrs s ["enable" "extraOptions"];

  configFile = toml.generate "dedicated.toml" (cfg.settings
    // {
      server = map serverToml (lib.attrValues enabledServers);
    });

  playlistsDir = pkgs.linkFarm "reclaimer-playlists" (lib.mapAttrsToList (name: playlist: {
      name = "${name}.playlist.json";
      path = json.generate "${name}.playlist.json" playlist;
    })
    cfg.playlists);

  bansSeed = json.generate "bans.json" {
    players = [];
    ips = [];
  };

  containerName = id: "reclaimer-${id}";

  # `dedicated <args>` inside a running server's container, as root on the host.
  # Without -s it uses the first server's container with RECLAIMER_DEDICATED_ONLY
  # cleared, so `status` covers every server; that is upstream's documented
  # `docker compose exec -e RECLAIMER_DEDICATED_ONLY= server-1 dedicated status`.
  # Bans and VPN allowances live in the shared bans.json, so they apply to every
  # server whichever container runs them.
  cli = pkgs.writeShellApplication {
    name = "reclaimer";
    runtimeInputs = [config.virtualisation.podman.package];
    text = ''
      usage() {
        echo "usage: reclaimer [-s <server>] <dedicated command> [args...]" >&2
        echo "servers: ${lib.concatStringsSep " " (lib.attrNames enabledServers)}" >&2
        echo "e.g. reclaimer status | reclaimer ban <player ID> --reason \"...\" | reclaimer -s <server> rcon players" >&2
        exit 2
      }
      env=(-e RECLAIMER_DEDICATED_ONLY=)
      server=${lib.escapeShellArg (lib.head (lib.attrNames enabledServers ++ [""]))}
      if [ "''${1:-}" = "-s" ]; then
        [ $# -ge 2 ] || usage
        server=$2
        env=()
        shift 2
      fi
      [ $# -ge 1 ] || usage
      tty=()
      [ -t 0 ] && tty=(-t)
      exec podman exec -i "''${tty[@]}" "''${env[@]}" "reclaimer-$server" dedicated "$@"
    '';
  };

  serverModule = {name, ...}: {
    freeformType = toml.type;
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to run this server. Disabled servers are left out of dedicated.toml and get no container.";
      };
      name = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Name shown in the Server Browser. Unique, at most 48 characters.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        description = "UDP game port, unique per server. RCON, when enabled, listens on TCP at the same number.";
      };
      extraOptions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["--memory=3g" "--cpus=2"];
        description = ''
          Extra `podman run` options for this server's container, such as
          resource caps. Upstream measures about 85 MB idle, 0.6-0.9 GB in a
          game and 1.4 GB briefly while a map loads; a 63-player game wants a
          core of its own.
        '';
      };
    };
  };
in {
  options.services.reclaimer = {
    enable = lib.mkEnableOption "Project Reclaimer (Halo 3) dedicated servers";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/projectreclaimer/project-reclaimer-dedicated:latest";
      example = "ghcr.io/projectreclaimer/project-reclaimer-dedicated:0.9.11";
      description = ''
        Container image. A server admits only players on exactly its own
        Project Reclaimer version, and releases come out several times a
        week, so the default follows `latest` (re-checked whenever a container
        starts) and `settings.auto_update` installs releases in between.
        Pinning a tag means updating it by hand with every release.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/reclaimer";
      description = ''
        The server folder, mounted at /server: bans.json, content/, data/
        (per-server logs, chat logs, status) and the executable copies
        auto-update writes. Shared by every server's container.
      '';
    };

    gameDir = lib.mkOption {
      type = lib.types.path;
      default = "${cfg.dataDir}/game";
      defaultText = lib.literalExpression ''"''${config.services.reclaimer.dataDir}/game"'';
      description = ''
        Halo 3's files from your own MCC install, mounted read-only at
        /server/game. It must hold halo3/halo3.dll, halo3/maps/shared.map and
        every map hosted (halo3/maps/<map>.map with halo3/maps/info/<map>.mapinfo);
        campaign.map and 040_voi.map are needed for Forge maps with campaign
        vehicles and AI, and the campaign missions for co-op servers. About
        5.5 GB for every multiplayer map, 4 GB more for the campaign.
      '';
    };

    cacheDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/cache/reclaimer";
      description = "Mounted at /cache: the Forge object library (about 340 MB, rebuilt after each update).";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "reclaimer";
      description = ''
        Owner of `dataDir`. The containers start as root and the image's
        entrypoint drops to the owner of /server, so this decides who owns
        what the servers write.
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "reclaimer";
      description = "Group of `dataDir`.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open every enabled server's UDP game port and, when the master is enabled, its TCP port.";
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [];
      example = lib.literalExpression ''[config.age.secrets.reclaimer-env.path]'';
      description = ''
        Environment files for every container, for secrets kept out of the
        store: RECLAIMER_DEDICATED_RCON_PASSWORD, RECLAIMER_DEDICATED_PASSWORD
        (the [defaults] join password). Every RECLAIMER_DEDICATED_* variable
        overrides the matching setting outside [[server]]; a misspelt one
        stops the start.
      '';
    };

    settings = lib.mkOption {
      default = {};
      description = ''
        Everything in dedicated.toml outside [[server]]: general settings,
        [master], [rcon], [defaults], [workshop], [vpn]. See
        https://projectreclaimer.dev/host#the-configuration-file. Relative
        paths resolve against /server.
      '';
      example = lib.literalExpression ''
        {
          host_name = "My Community";
          admins = ["<64 hex player ID>"];
          defaults = { max_players = 16; block_vpn = true; };
        }
      '';
      type = lib.types.submodule {
        freeformType = toml.type;
        options = {
          auto_update = lib.mkOption {
            type = lib.types.bool;
            # Upstream's default is false. On here because a server only admits
            # players on exactly its version, so a server that lags a release
            # is empty until someone updates it.
            default = true;
            description = ''
              Install new stable releases hourly and restart the servers,
              ending games under way. Each container keeps its updated copy
              under /server/.reclaimer; a new image resets it to the image's.
            '';
          };
          master = lib.mkOption {
            default = {};
            description = "This machine's discovery master. The first container to start serves it; the others report to it.";
            type = lib.types.submodule {
              freeformType = toml.type;
              options = {
                enabled = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Run this machine's master.";
                };
                port = lib.mkOption {
                  type = lib.types.port;
                  default = 49175;
                  description = "The master's TCP port.";
                };
              };
            };
          };
        };
      };
    };

    playlists = lib.mkOption {
      type = lib.types.attrsOf json.type;
      default = {};
      example = lib.literalExpression ''
        {
          rotation = {
            version = 2;
            name = "Community Rotation";
            games = [
              { map = "Guardian"; game = "Slayer"; weight = 2; }
              { map = "Valhalla"; game = "Capture the Flag"; }
              { map = "The Pit"; game = "Slayer"; options."rounds.teams" = 1; name = "Team Slayer"; }
            ];
          };
        }
      '';
      description = ''
        Playlist files. `<name>` becomes /server/playlists/<name>.playlist.json,
        which a server uses with `playlist = "playlists/<name>.playlist.json"`.
        When set, /server/playlists is this read-only set and nothing else.
        A playlist needs 3 to 128 games with no repeats; see
        https://projectreclaimer.dev/host#custom-playlists.
      '';
    };

    servers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule serverModule);
      default = {};
      example = lib.literalExpression ''
        {
          slayer = { name = "Guardian Slayer"; port = 49176; map = "Guardian"; game = "Slayer"; };
          coop = { port = 49177; max_players = 4; campaign = { mission = 3010; difficulty = "heroic"; }; };
        }
      '';
      description = ''
        One [[server]] each, run in its own container named reclaimer-<attr name>.
        Besides `enable`, `name`, `port` and `extraOptions`, every key is
        passed through to the [[server]] block: one of `playlist`, `map` +
        `game`, `variant` or `campaign`, and optional ones such as
        `max_players`, `min_players`, `password`, `hidden`, `share_mods`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = let
      servers = lib.attrValues enabledServers;
      ports = map (s: s.port) servers;
      names = map (s: s.name) servers;
    in
      [
        {
          assertion = servers != [];
          message = "services.reclaimer: enable at least one server in services.reclaimer.servers.";
        }
        {
          assertion = lib.length (lib.unique ports) == lib.length ports;
          message = "services.reclaimer: every server needs its own port.";
        }
        {
          assertion = lib.length (lib.unique names) == lib.length names;
          message = "services.reclaimer: every server needs its own name.";
        }
        {
          # RCON listens on TCP at the game port, which would collide.
          assertion = !(lib.elem cfg.settings.master.port ports);
          message = "services.reclaimer: no server may use the master's port ${toString cfg.settings.master.port}.";
        }
      ]
      ++ map (s: {
        assertion = lib.stringLength s.name <= 48;
        message = "services.reclaimer: server name '${s.name}' is longer than 48 characters.";
      })
      servers
      ++ map (s: {
        assertion = s.port >= 1024;
        message = "services.reclaimer: server '${s.name}' port must be 1024 or above.";
      })
      servers;

    virtualisation.podman.enable = true;

    virtualisation.oci-containers.containers = lib.mapAttrs' (id: s:
      lib.nameValuePair (containerName id) {
        image = cfg.image;
        # Checks the registry on every start and keeps the local image when
        # the pull fails, so a `latest` image follows releases without
        # making the servers depend on ghcr being up.
        pull = "newer";
        volumes =
          [
            "${cfg.dataDir}:/server"
            "${cfg.gameDir}:/server/game:ro"
            # The entrypoint only writes a dedicated.toml when there is none,
            # and the servers never write it (RCON changes last until restart).
            # Being a store path in the run line, an edit restarts the
            # containers on switch.
            "${configFile}:/server/dedicated.toml:ro"
            "${cfg.cacheDir}:/cache"
          ]
          ++ lib.optional (cfg.playlists != {}) "${playlistsDir}:/server/playlists:ro";
        environment = {
          # Picks this container's [[server]], by game port.
          RECLAIMER_DEDICATED_ONLY = toString s.port;
        };
        inherit (cfg) environmentFiles;
        extraOptions =
          [
            # As upstream's compose.yaml. The containers share one master:
            # the first to start binds its TCP port, the others' servers
            # report to it over the host's network, and another takes over
            # if that container stops. RCON stays on the host's 127.0.0.1.
            "--network=host"
            "--security-opt=no-new-privileges"
            # The supervisor stops its server cleanly on SIGINT (the image's
            # STOPSIGNAL); upstream allows it 30 seconds.
            "--stop-timeout=30"
          ]
          ++ s.extraOptions;
      })
    enabledServers;

    users.users = lib.mkIf (cfg.user == "reclaimer") {
      reclaimer = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.dataDir;
        description = "Project Reclaimer dedicated servers";
      };
    };
    users.groups = lib.mkIf (cfg.group == "reclaimer") {reclaimer = {};};

    # The folders `dedicated init` would make; with dedicated.toml present the
    # entrypoint never runs it. Mount points for the read-only mounts too, so
    # the runtime does not create them as root.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.dataDir}/content 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.dataDir}/content/Maps 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.dataDir}/content/Game Modes' 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.dataDir}/content/Mods 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.dataDir}/data 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.dataDir}/game 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.dataDir}/playlists 0750 ${cfg.user} ${cfg.group} - -"
      "f ${cfg.dataDir}/dedicated.toml 0640 ${cfg.user} ${cfg.group} - -"
      # The same empty list `dedicated init` writes. C copies only when the
      # file is missing; the servers and `reclaimer ban` edit it in place.
      "C ${cfg.dataDir}/bans.json - - - - ${bansSeed}"
      "z ${cfg.dataDir}/bans.json 0640 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.cacheDir} 0750 ${cfg.user} ${cfg.group} - -"
    ];

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedUDPPorts = map (s: s.port) (lib.attrValues enabledServers);
      allowedTCPPorts = lib.optional cfg.settings.master.enabled cfg.settings.master.port;
    };

    environment.systemPackages = [cli];
  };
}
