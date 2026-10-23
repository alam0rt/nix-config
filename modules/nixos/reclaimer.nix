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
# install or downloaded from Steam with `reclaimer-fetch-game <account>`; until
# they are there each container logs what is missing and re-runs
# `dedicated check` every 15 seconds.
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

  playlistFiles = lib.mapAttrs' (name: playlist:
    lib.nameValuePair "${name}.playlist.json" (json.generate "${name}.playlist.json" playlist))
  cfg.playlists;

  # From 0.9.18 the servers watch dedicated.toml and the playlists and apply
  # edits without a restart (auto_reload, on by default), keeping players in
  # and their games going. So both are copied into dataDir by a unit of their
  # own rather than mounted from the store, which would put store paths in
  # the containers' run lines and restart every server on any edit. Only the
  # settings that apply when dedicated restarts restart the containers.
  autoReload = cfg.settings.auto_reload or true;
  restartTriggers =
    if autoReload
    then [
      (json.generate "reclaimer-restart-settings.json" {
        settings = lib.filterAttrs (n: _:
          lib.elem n ["public_address" "auto_update" "auto_reload" "master" "workshop" "game" "content" "data"])
        cfg.settings;
        vpn = lib.filterAttrs (n: _: lib.elem n ["lists" "asns"]) (cfg.settings.vpn or {});
      })
    ]
    else [configFile] ++ lib.attrValues playlistFiles ++ lib.attrValues cfg.content;

  installConfig = let
    put = src: dst: "put ${src} ${lib.escapeShellArg dst}\n";
  in ''
    # Only when it differs, and by rename, so the servers never see a file
    # half written or reload for nothing.
    put() {
      if ! cmp -s "$1" "$2"; then
        install -d -m 0750 -o ${lib.escapeShellArg cfg.user} -g ${lib.escapeShellArg cfg.group} "$(dirname "$2")"
        install -m 0640 -o ${lib.escapeShellArg cfg.user} -g ${lib.escapeShellArg cfg.group} "$1" "$2.nix-new"
        mv -f "$2.nix-new" "$2"
      fi
    }
    # The same empty list `dedicated init` writes, only when there is none:
    # the servers and `reclaimer ban` edit it in place. Not a tmpfiles C+z,
    # which leaves it root's: tmpfiles won't chown a root-owned file in a
    # folder that isn't root's ("unsafe path transition").
    bans=${lib.escapeShellArg "${cfg.dataDir}/bans.json"}
    [ -e "$bans" ] || cp ${bansSeed} "$bans"
    chown ${lib.escapeShellArg "${cfg.user}:${cfg.group}"} "$bans"
    chmod 0640 "$bans"

    ${put configFile "${cfg.dataDir}/dedicated.toml"}${lib.concatStrings (lib.mapAttrsToList (name: file: put file "${cfg.dataDir}/playlists/${name}") playlistFiles)}${lib.concatStrings (lib.mapAttrsToList (name: file: put file "${cfg.dataDir}/content/${name}") cfg.content)}
  '';

  # Halo 3's server files from MCC (app 976730) on Steam: every depot the
  # account owns, filtered down to what `gameDir` needs. Halo 3 is one of
  # MCC's DLC depots; asking for the app rather than depot IDs finds it.
  gameFileList = pkgs.writeText "reclaimer-game-files.txt" ''
    regex:^halo3/halo3\.dll$
    regex:^halo3/maps/
  '';

  fetchGame = pkgs.writeShellApplication {
    name = "reclaimer-fetch-game";
    runtimeInputs = [pkgs.depotdownloader];
    text = ''
      if [ $# -lt 1 ]; then
        echo "usage: reclaimer-fetch-game <Steam account> [DepotDownloader options...]" >&2
        echo "Downloads halo3/halo3.dll and halo3/maps from MCC into ${cfg.gameDir}." >&2
        echo "Run it again to update; -validate re-checks every file." >&2
        exit 2
      fi
      dir=${lib.escapeShellArg cfg.gameDir}
      if [ ! -w "$dir" ]; then
        echo "reclaimer-fetch-game: $dir is not writable by $(id -un); run it as the folder's owner" >&2
        exit 1
      fi
      account=$1
      shift
      # MCC is Windows-only; DepotDownloader would otherwise skip every depot
      # as not for Linux. -remember-password keeps a login token, never the
      # password, so later runs skip Steam Guard.
      exec DepotDownloader -app 976730 -os windows -osarch 64 \
        -username "$account" -remember-password \
        -dir "$dir" -filelist ${gameFileList} "$@"
    '';
  };

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
      example = "ghcr.io/projectreclaimer/project-reclaimer-dedicated:0.9.23";
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
        `reclaimer-fetch-game <Steam account>`, run as the folder's owner,
        downloads all of it from Steam.
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

        The file is copied to `dataDir`/dedicated.toml on every switch and
        boot (hand edits there last until then). With `auto_reload` (on
        unless set false) the servers apply most edits without a restart;
        the containers restart only for settings that need it:
        `public_address`, `auto_update`, `auto_reload`, [master], [workshop],
        [vpn] `lists`/`asns`, `game`, `content`, `data`.
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
        They are copied into `dataDir`/playlists on every switch and boot,
        replacing files of the same name; servers take up a changed playlist
        from their next vote. A playlist needs 3 to 128 games with no repeats; see
        https://projectreclaimer.dev/host#custom-playlists.
      '';
    };

    content = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      example = lib.literalExpression ''{"Maps/my_arena.mvar" = ./my_arena.mvar;}'';
      description = ''
        Files for the shared content folder, /server/content, by their path
        under it: saved maps and Forge map variants in Maps/ (.mvar, .json),
        saved game types in Game Modes/. Copied in on every switch and boot,
        beside whatever else is there; running servers take up new and
        changed ones by themselves. A playlist or server names a saved map
        as "Maps/<file>", or by the name stored in it.
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
        volumes = [
          "${cfg.dataDir}:/server"
          "${cfg.gameDir}:/server/game:ro"
          "${cfg.cacheDir}:/cache"
        ];
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

    systemd.services =
      {
        reclaimer-config = {
          description = "Project Reclaimer dedicated.toml, playlists and content";
          wantedBy = ["multi-user.target"];
          after = ["systemd-tmpfiles-setup.service" "systemd-tmpfiles-resetup.service"];
          path = [pkgs.diffutils];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          # The store paths in it re-run it on switch whenever they change.
          script = installConfig;
        };
      }
      // lib.mapAttrs' (id: _:
        lib.nameValuePair "${config.virtualisation.oci-containers.backend}-${containerName id}" {
          # Wants, not Requires: a Requires would pass the config unit's
          # restart on to the containers, which is what this avoids. The
          # entrypoint writes a default dedicated.toml when there is none, so
          # ours must be in place first.
          wants = ["reclaimer-config.service"];
          after = ["reclaimer-config.service"];
          inherit restartTriggers;
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
      "d ${cfg.cacheDir} 0750 ${cfg.user} ${cfg.group} - -"
    ];

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedUDPPorts = map (s: s.port) (lib.attrValues enabledServers);
      allowedTCPPorts = lib.optional cfg.settings.master.enabled cfg.settings.master.port;
    };

    environment.systemPackages = [cli fetchGame];
  };
}
