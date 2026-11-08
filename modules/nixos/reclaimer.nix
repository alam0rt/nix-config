# Project Reclaimer dedicated servers (Halo 3, ODST, and early Reach, CE and
# Halo 2 multiplayer on MCC's files). https://projectreclaimer.dev/host
#
# From 0.10 the server is a native Linux program: a recompiled engine with no
# Wine, display, GPU or sound device. This runs upstream's own Linux setup: one
# `project-reclaimer dedicated` in `dataDir`, whose supervisor starts every
# [[server]] as a process of its own, restarts any that stops, and runs this
# machine's master. Upstream's Linux release links only glibc and libgcc_s.
#
# Versions: a server admits only players on exactly its own release, and
# releases come out several times a week. So the program runs from a writable
# copy in `homeDir`/program, seeded from `package` (pkgs/project-reclaimer-dedicated)
# and replaced in place by upstream's `auto_update`, through nix-ld. A newer
# seed (bump the package) replaces the copy on the next start.
#
# Game files are not included. Halo 3's (halo3/halo3.dll, halo3/maps/...) go in
# `gameDir`, copied from your own MCC install or downloaded from Steam with
# `reclaimer-fetch-game <account>`; until they are there the servers log what
# is missing and re-check every 15 seconds.
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
  enabledBots = lib.filterAttrs (_: b: b.enable) cfg.bots;

  # `enable` is for this module; everything else in a server's attrset is a
  # [[server]] key of dedicated.toml.
  serverToml = s: removeAttrs s ["enable"];

  steamcmd = cfg.workshop.steamcmd.enable;

  # Workshop items go to dedicated.toml only with SteamCMD: a server asked for
  # an item it can't download (no Steam app here) refuses to start.
  workshopSettings = lib.optionalAttrs steamcmd {
    workshop =
      {
        items = map lib.toInt cfg.workshop.items;
        steamcmd = lib.getExe cfg.workshop.steamcmd.package;
        username = cfg.workshop.username;
      }
      // (cfg.settings.workshop or {});
  };

  settings =
    {game = toString cfg.gameDir;}
    // cfg.settings
    // workshopSettings;

  configFile = toml.generate "dedicated.toml" (settings
    // {
      server = map serverToml (lib.attrValues enabledServers);
    });

  playlistFiles = lib.mapAttrs' (name: playlist:
    lib.nameValuePair "${name}.playlist.json" (json.generate "${name}.playlist.json" playlist))
  cfg.playlists;

  # With auto_reload (on unless set false) the supervisor watches
  # dedicated.toml, the playlists and content/, and applies edits without a
  # restart, keeping players in and their games going; settings that need a
  # new server restart that server once it is empty. So all of them are copied
  # into dataDir by a unit of their own, and only what upstream applies "when
  # dedicated restarts" (or not at all) restarts reclaimer.service.
  autoReload = settings.auto_reload or true;
  restartKeys = [
    "public_address"
    "bind_address"
    "upnp"
    "auto_update"
    "auto_reload"
    "master"
    "workshop"
    "game"
    "content"
    "data"
  ];
  # Per-server settings that a reload doesn't apply.
  serverRestartKeys = [
    "coop_network"
    "odst_objects"
    "halo3_objects"
    "reach_objects"
    "halo1_objects"
    "halo2_objects"
    "forge_mods"
    "forge_primitives"
  ];
  restartTriggers =
    if autoReload
    then [
      (json.generate "reclaimer-restart-settings.json" {
        settings = lib.filterAttrs (n: _: lib.elem n restartKeys) settings;
        vpn = lib.filterAttrs (n: _: lib.elem n ["lists" "asns" "asn_table"]) (settings.vpn or {});
        defaults = lib.filterAttrs (n: _: lib.elem n serverRestartKeys) (settings.defaults or {});
        servers = lib.mapAttrs (_: s: lib.filterAttrs (n: _: lib.elem n serverRestartKeys) s) enabledServers;
      })
    ]
    else [configFile] ++ lib.attrValues playlistFiles ++ lib.attrValues cfg.content;

  # Mounted into the service's (and the `reclaimer` command's) view of
  # content/Mods: the hand-fetched mods read-only, the Workshop downloads
  # read-write. Both hold gigabytes, so they live outside dataDir. Bind
  # mounts, not symlinks: the servers skip symlinks inside content/Mods, and
  # find mods a folder deeper (Fetched/<id>) fine (both checked on 0.10.1).
  modsMount = "${cfg.dataDir}/content/Mods/Fetched";
  workshopMount = "${cfg.dataDir}/content/Mods/Workshop";
  bindReadOnlyPaths = lib.optional (cfg.modsDir != null) "${toString cfg.modsDir}:${modsMount}";
  bindPaths = lib.optional (cfg.workshop.dir != null) "${toString cfg.workshop.dir}:${workshopMount}";

  # The program is upstream's unpatched Linux build, run from a writable copy
  # through nix-ld. nix-ld's defaults (its ld.so and libraries under
  # /run/current-system/sw/share/nix-ld) cover glibc and libgcc_s: checked on
  # sauron with `env -i`, as a unit runs it, so no NIX_LD variables here, and
  # none leak into SteamCMD's steam-run. The supervisor re-executes its own
  # file for each server, so it must stay a real file, not a store wrapper.
  environment = {
    HOME = cfg.homeDir;
    RECLAIMER_CACHE_DIR = cfg.cacheDir;
    # Release downloads, the VPN lists and the stats service go over HTTPS.
    SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
  };

  programDir = "${cfg.homeDir}/program";

  # Seeds the writable copy from `package` when there is none, or when the
  # package is newer than the seed last copied (the marker). Then runs it.
  # auto_update replaces the copy in place between seeds; a seed older than
  # what auto_update installed is never copied, but a newer seed always is,
  # even over a still newer update (auto_update brings that back within the
  # hour).
  run = pkgs.writeShellApplication {
    name = "reclaimer-run";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      prog=${lib.escapeShellArg programDir}
      seed=${cfg.package}/share/project-reclaimer
      seed_version=${lib.escapeShellArg cfg.package.version}
      marker="$prog/.nix-seed-version"
      installed=$(cat "$marker" 2>/dev/null || echo 0)
      newest=$(printf '%s\n%s\n' "$installed" "$seed_version" | sort -V | tail -n1)
      if [ ! -x "$prog/project-reclaimer" ] || { [ "$newest" = "$seed_version" ] && [ "$installed" != "$seed_version" ]; }; then
        echo "reclaimer: installing Project Reclaimer $seed_version into $prog" >&2
        rm -rf "$prog.new" "$prog.old"
        cp -r --no-preserve=mode,ownership "$seed" "$prog.new"
        chmod 0755 "$prog.new/project-reclaimer"
        echo "$seed_version" > "$prog.new/.nix-seed-version"
        if [ -e "$prog" ]; then mv "$prog" "$prog.old"; fi
        mv "$prog.new" "$prog"
        rm -rf "$prog.old"
      fi
      exec "$prog/project-reclaimer" "$@"
    '';
  };

  # Halo 3's server files from MCC (app 976730) on Steam: every depot the
  # account owns, filtered down to what `gameDir` needs for `fetchGames`. Each
  # game is one of MCC's DLC depots; asking for the app rather than depot IDs
  # finds them. The variant folders hold each game's own and MCC's matchmaking
  # game and map variants, a few MB in all. Servers play no sound or movies, so
  # fmod/ and bink/ are left out where upstream's `dedicated init` leaves them
  # out; `dedicated check` names any file a server still lacks.
  gameFilePatterns = {
    halo3 = [
      "regex:^halo3/halo3\\.dll$"
      "regex:^halo3/maps/"
      "regex:^halo3/(hopper_)?(game|map)_variants/"
    ];
    odst = [
      "regex:^halo3odst/halo3odst\\.dll$"
      "regex:^halo3odst/maps/"
      "regex:^halo3odst/(hopper_)?(game|map)_variants/"
    ];
    reach = [
      "regex:^haloreach/haloreach\\.dll$"
      "regex:^haloreach/maps/"
      "regex:^haloreach/(hopper_)?(game|map)_variants/"
    ];
    # Combat Evolved's and Halo 2's engines read their own shared files and
    # sounds; upstream's init copies those "with each game's engine".
    halo1 = [
      "regex:^halo1/halo1\\.dll$"
      "regex:^halo1/maps/"
      "regex:^halo1/shaders/"
      "regex:^halo1/[^/]+\\.dat$"
      "regex:^halo1/(hopper_)?(game|map)_variants/"
    ];
    halo2 = [
      "regex:^halo2/halo2\\.dll$"
      "regex:^halo2/h2_maps_win64_dx11/"
      "regex:^halo2/maps/"
      "regex:^halo2/(hopper_)?(game|map)_variants/"
    ];
  };
  gameFileList =
    pkgs.writeText "reclaimer-game-files.txt" (lib.concatLines
      (lib.concatMap (g: gameFilePatterns.${g}) (lib.unique (["halo3"] ++ cfg.fetchGames))));

  fetchGame = pkgs.writeShellApplication {
    name = "reclaimer-fetch-game";
    runtimeInputs = [pkgs.depotdownloader];
    text = ''
      if [ $# -lt 1 ]; then
        echo "usage: reclaimer-fetch-game <Steam account> [DepotDownloader options...]" >&2
        echo "Downloads ${lib.concatStringsSep ", " (lib.unique (["halo3"] ++ cfg.fetchGames))} from MCC into ${toString cfg.gameDir}." >&2
        echo "Run it again to update; -validate re-checks every file." >&2
        exit 2
      fi
      dir=${lib.escapeShellArg (toString cfg.gameDir)}
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

  # Hand-fetched Workshop mods into `modsDir`, one folder per item named by its
  # ID, as Steam lays out steamapps/workshop/content/976730. For servers
  # without SteamCMD; with it, the servers download and update the items
  # themselves.
  fetchWorkshop = pkgs.writeShellApplication {
    name = "reclaimer-fetch-workshop";
    runtimeInputs = [pkgs.depotdownloader];
    text = ''
      if [ $# -lt 1 ]; then
        echo "usage: reclaimer-fetch-workshop <Steam account> [item ID...]" >&2
        echo "Downloads Workshop items into ${toString cfg.modsDir}; with no IDs, the configured ones:" >&2
        echo "  ${lib.concatStringsSep " " cfg.workshop.items}" >&2
        echo "Restart reclaimer.service after a mod changes." >&2
        exit 2
      fi
      dir=${lib.escapeShellArg (toString cfg.modsDir)}
      if [ ! -w "$dir" ]; then
        echo "reclaimer-fetch-workshop: $dir is not writable by $(id -un); run it as the folder's owner" >&2
        exit 1
      fi
      account=$1
      shift
      items=("$@")
      [ ''${#items[@]} -gt 0 ] || items=(${lib.escapeShellArgs cfg.workshop.items})
      for id in "''${items[@]}"; do
        echo "== Workshop item $id"
        DepotDownloader -app 976730 -pubfile "$id" \
          -username "$account" -remember-password -dir "$dir/$id"
      done
    '';
  };

  bansSeed = json.generate "bans.json" {
    players = [];
    ips = [];
  };

  installConfig = let
    put = src: dst: "put ${src} ${lib.escapeShellArg dst}\n";
    owner = lib.escapeShellArg "${cfg.user}:${cfg.group}";
    dir = path: "install -d -m 0750 -o ${lib.escapeShellArg cfg.user} -g ${lib.escapeShellArg cfg.group} ${lib.escapeShellArg path}\n";
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
    chown ${owner} "$bans"
    chmod 0640 "$bans"

    # Mount points for the mod folders, and the Workshop folder itself, which
    # may sit where tmpfiles refuses to go (a share owned by someone else).
    ${lib.optionalString (cfg.modsDir != null) (dir modsMount)}${lib.optionalString (cfg.workshop.dir != null) ''
      ${dir workshopMount}install -d -m 0755 ${lib.escapeShellArg (toString cfg.workshop.dir)}
      chown ${owner} ${lib.escapeShellArg (toString cfg.workshop.dir)}
    ''}
    ${put configFile "${cfg.dataDir}/dedicated.toml"}${lib.concatStrings (lib.mapAttrsToList (name: file: put file "${cfg.dataDir}/playlists/${name}") playlistFiles)}${lib.concatStrings (lib.mapAttrsToList (name: file: put file "${cfg.dataDir}/content/${name}") cfg.content)}
  '';

  # `project-reclaimer dedicated <args>` as the service user, with the
  # service's environment and mod mounts, through systemd-run (so root is
  # needed). Without -s it covers every server; -s <server> narrows it to one,
  # as RECLAIMER_DEDICATED_ONLY does for a container per server.
  serverPorts = lib.mapAttrs (_: s: toString s.port) enabledServers;
  cli = pkgs.writeShellApplication {
    name = "reclaimer";
    runtimeInputs = [config.systemd.package];
    text = ''
      usage() {
        echo "usage: reclaimer [-s <server>] <dedicated command> [args...]" >&2
        echo "servers: ${lib.concatStringsSep " " (lib.attrNames enabledServers)}" >&2
        echo "e.g. reclaimer status | reclaimer check | reclaimer content guardian | reclaimer ban <player ID> --reason \"...\" | reclaimer -s <server> rcon players" >&2
        exit 2
      }
      only=()
      if [ "''${1:-}" = "-s" ]; then
        [ $# -ge 2 ] || usage
        case "$2" in
          ${lib.concatStrings (lib.mapAttrsToList (id: port: "${lib.escapeShellArg id}) only=(--setenv=RECLAIMER_DEDICATED_ONLY=${port}) ;;\n    ") serverPorts)}*) echo "reclaimer: no server '$2'" >&2; usage ;;
        esac
        shift 2
      fi
      [ $# -ge 1 ] || usage
      io=(--pipe)
      [ -t 0 ] && [ -t 1 ] && io=(--pty)
      exec systemd-run --quiet --wait --collect --service-type=exec "''${io[@]}" \
        --uid=${lib.escapeShellArg cfg.user} --gid=${lib.escapeShellArg cfg.group} \
        --working-directory=${lib.escapeShellArg cfg.dataDir} \
        ${lib.concatMapStrings (e: "--setenv=${lib.escapeShellArg e} ") (lib.mapAttrsToList (n: v: "${n}=${v}") environment)}\
        ${lib.concatMapStrings (f: "--property=EnvironmentFile=${lib.escapeShellArg (toString f)} ") cfg.environmentFiles}\
        ${lib.concatMapStrings (p: "--property=BindReadOnlyPaths=${lib.escapeShellArg p} ") bindReadOnlyPaths}\
        ${lib.concatMapStrings (p: "--property=BindPaths=${lib.escapeShellArg p} ") bindPaths}\
        "''${only[@]}" \
        ${lib.getExe run} dedicated --config ${lib.escapeShellArg "${cfg.dataDir}/dedicated.toml"} "$@"
    '';
  };

  serverModule = {name, ...}: {
    freeformType = toml.type;
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to run this server. Disabled servers are left out of dedicated.toml.";
      };
      name = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Name shown in the Server Browser. Unique, at most 48 characters; its folder under data/ is made from it.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        description = "UDP game port, unique per server. RCON, when enabled, listens on TCP at the same number unless `rcon_port` says otherwise.";
      };
    };
  };

  botModule = {name, ...}: {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to run this bot.";
      };
      name = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "The bot's name in chat and voice: 1 to 15 letters, numbers, spaces, `_` or `-`. Players see it with [BOT].";
      };
      server = lib.mkOption {
        type = lib.types.str;
        example = "rotation";
        description = "The `services.reclaimer.servers` entry it joins, on this machine.";
      };
      keyFile = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.homeDir}/bots/${name}.key";
        defaultText = lib.literalExpression ''"''${config.services.reclaimer.homeDir}/bots/<name>.key"'';
        description = ''
          The bot's identity. Made on its first start if missing, which logs
          the bot's player ID: give that ID a role that can `bots.run`
          (`settings.roles.<role>.players`) and set `settings.defaults.allow_bots`.
        '';
      };
      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["--input" "wav:/srv/music/loop.wav" "--loop"];
        description = "More `reclaimer-bot join` options: --input, --loop, --output, --password. See BOT.md in the package's share/doc.";
      };
    };
  };
in {
  options.services.reclaimer = {
    enable = lib.mkEnableOption "Project Reclaimer (Halo 3) dedicated servers";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../pkgs/project-reclaimer-dedicated {};
      defaultText = lib.literalExpression "pkgs.project-reclaimer-dedicated";
      description = ''
        Upstream's Linux server package, used only as the seed of the writable
        copy in `homeDir`/program that the servers run and `auto_update`
        replaces. A newer package replaces that copy on the next start.
      '';
    };

    botPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../pkgs/reclaimer-bot {};
      defaultText = lib.literalExpression "pkgs.reclaimer-bot";
      description = "reclaimer-bot, for `bots`.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/reclaimer";
      description = ''
        The server folder: dedicated.toml, bans.json, playlists/, content/ and
        data/ (each server's log, chat logs, live status, keys and films; the
        master's log; data/stats-key.json, which a whitelisted stats service
        knows the servers by).
      '';
    };

    homeDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/reclaimer-home";
      description = ''
        The service user's home: the writable program copy (program/) that
        `auto_update` replaces, the player folder
        (.local/share/ProjectReclaimer) and SteamCMD's Steam root and saved
        sign-in. A few hundred MB.
      '';
    };

    gameDir = lib.mkOption {
      type = lib.types.path;
      default = "${cfg.dataDir}/game";
      defaultText = lib.literalExpression ''"''${config.services.reclaimer.dataDir}/game"'';
      description = ''
        Halo 3's files from your own MCC install, read only (dedicated.toml's
        `game`). It must hold halo3/halo3.dll, halo3/maps/shared.map and every
        map hosted (halo3/maps/<map>.map with halo3/maps/info/<map>.mapinfo);
        campaign.map and 040_voi.map are needed for Forge maps with campaign
        vehicles and AI, and the campaign missions for co-op servers. About
        5.5 GB for every multiplayer map, 4 GB more for the campaign; ODST,
        Reach, CE and Halo 2 servers need those games' folders too
        (`fetchGames`). `reclaimer-fetch-game <Steam account>`, run as the
        folder's owner, downloads them from Steam.
      '';
    };

    fetchGames = lib.mkOption {
      type = lib.types.listOf (lib.types.enum ["halo3" "odst" "reach" "halo1" "halo2"]);
      default = ["halo3"];
      example = ["halo3" "odst" "reach" "halo1" "halo2"];
      description = ''
        The games `reclaimer-fetch-game` downloads into `gameDir`, besides
        Halo 3 (always): "odst" (Halo 3: ODST, about 3.5 GB), "reach",
        "halo1" (Combat Evolved) and "halo2". Their maps can then be played,
        mixed into one playlist with Halo 3's.
      '';
    };

    cacheDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/cache/reclaimer";
      description = "RECLAIMER_CACHE_DIR: the engine prepared from halo3.dll (once per release) and the Forge object library. A few hundred MB; rebuilt if deleted.";
    };

    modsDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/srv/games/halo3-mods";
      description = ''
        Mods copied in by hand, one folder per mod, mounted read-only at
        content/Mods/Fetched (Workshop mods run to gigabytes).
        `reclaimer-fetch-workshop <Steam account>`, run as the folder's
        owner, downloads `workshop.items` into it. The servers never update
        these: players can't join while their copy and the server's differ,
        so fetch again when an author updates one and restart
        reclaimer.service. With `workshop.steamcmd.enable` the servers manage
        Workshop items themselves; then this is for mods not on the Workshop.
      '';
    };

    workshop = {
      items = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["2984061723"];
        description = ''
          Steam Workshop item IDs. With `steamcmd.enable` they become
          [workshop] `items`, which the servers download before they start and
          keep current (hourly, swapping an item once the servers using it are
          empty); without it, `reclaimer-fetch-workshop` downloads them into
          `modsDir`. Name their maps in playlists by title, or as
          "workshop:<id>/<map file>" once SteamCMD is on (a workshop: name
          without it makes the server try a download it can't do, and refuse
          to start).
        '';
      };

      dir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/srv/games/halo3-workshop";
        description = ''
          Where Workshop downloads go, mounted read-write at
          content/Mods/Workshop (where upstream installs them). Null keeps
          them in `dataDir`. Created and given to the service user on start.
        '';
      };

      username = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The Steam account (name only) SteamCMD is signed in with; it must own MCC.";
      };

      steamcmd = {
        enable = lib.mkEnableOption ''
          Workshop downloads through SteamCMD. SteamCMD needs one interactive
          sign-in as the service user first, with the same home:
          `sudo -u <user> -H steamcmd +login <account> +quit`. Without it a
          Workshop download fails, which stops the servers' start
        '';
        package = lib.mkPackageOption pkgs "steamcmd" {};
      };
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "reclaimer";
      description = "Account the servers run as; owns `dataDir`, `homeDir` and `cacheDir`.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "reclaimer";
      description = "Group of `user`.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open every enabled server's UDP game port and, when the master is enabled, its port on TCP and UDP.";
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [];
      example = lib.literalExpression ''[config.age.secrets.reclaimer-env.path]'';
      description = ''
        Environment files for the servers, for secrets kept out of the store:
        RECLAIMER_DEDICATED_RCON_PASSWORD, RECLAIMER_DEDICATED_PASSWORD (the
        [defaults] join password). Every RECLAIMER_DEDICATED_* variable
        overrides the matching setting outside [[server]]; a misspelt one
        stops the start.
      '';
    };

    serviceConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      example = {
        MemoryMax = "12G";
        CPUQuota = "400%";
      };
      description = ''
        Extra [Service] settings for reclaimer.service, which runs every
        server: resource caps such as MemoryMax, MemoryHigh, CPUQuota or
        CPUWeight. Upstream says about 110 MB a server waiting for players
        and 0.6-0.9 GB and up to a core of its own in a full game; 0.10.1
        on sauron measured about 1.2 GB a server idle, and about a core
        each for the first minute after a start.
      '';
    };

    settings = lib.mkOption {
      default = {};
      description = ''
        Everything in dedicated.toml outside [[server]]: general settings,
        [master], [rcon], [defaults], [workshop], [vpn], [roles.*]. See
        https://projectreclaimer.dev/host#the-configuration-file. Relative
        paths resolve against `dataDir`. `game` defaults to `gameDir`.

        The file is copied to `dataDir`/dedicated.toml on every switch and
        boot (hand edits there last until then). With `auto_reload` (on
        unless set false) the servers apply most edits without a restart;
        reclaimer.service restarts only for settings upstream applies when
        dedicated restarts: `public_address`, `bind_address`, `upnp`,
        `auto_update`, `auto_reload`, [master], [workshop], [vpn]
        `lists`/`asns`/`asn_table`, `game`, `content`, `data`, and in
        [defaults] or a server `coop_network` and the Forge palette settings.
      '';
      example = lib.literalExpression ''
        {
          host_name = "My Community";
          admins = ["<64 hex player ID>"];
          defaults = { max_players = 16; tick_rate = 30; };
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
              Install new stable releases hourly into `homeDir`/program and
              restart the servers, ending games under way.
            '';
          };
          master = lib.mkOption {
            default = {};
            description = "This machine's discovery master, run by the supervisor; every server here reports to it.";
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
                  description = "The master's port, on TCP (browsers) and UDP (servers registering, NAT introductions).";
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
        Playlist files. `<name>` becomes playlists/<name>.playlist.json,
        which a server uses with `playlist = "playlists/<name>.playlist.json"`.
        They are copied into `dataDir`/playlists on every switch and boot,
        replacing files of the same name; servers take up a changed playlist
        from their next vote. A playlist holds 1 to 256 games with no repeats,
        voted on from three up; see
        https://projectreclaimer.dev/host#custom-playlists.
      '';
    };

    content = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      example = lib.literalExpression ''{"Maps/my_arena.mvar" = ./my_arena.mvar;}'';
      description = ''
        Files for the shared content folder by their path under it: saved
        maps and Forge map variants in Maps/ (.mvar, .json), game types and
        modes in Game Modes/ (.bin, .json, .rmeg), vote images in Images/.
        Copied in on every switch and boot, beside whatever else is there;
        running servers take up new and changed ones by themselves. A playlist
        or server names a saved map as "Maps/<file>", or by the name stored in
        it.
      '';
    };

    servers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule serverModule);
      default = {};
      example = lib.literalExpression ''
        {
          slayer = { name = "Guardian Slayer"; port = 49176; map = "Guardian"; game = "Slayer"; metrics_http = "127.0.0.1:9310"; };
          coop = { port = 49177; max_players = 16; campaign = { mission = 3010; difficulty = "heroic"; }; };
        }
      '';
      description = ''
        One [[server]] each, at most 32. Besides `enable`, `name` and `port`,
        every key is passed through to the [[server]] block: one of
        `playlist`, `map` + `game`, `variant`, `campaign` or `odst`, and any
        [defaults] setting or server-only one such as `host_name`, `admins`,
        `moderators`, `roles`, `rcon_port`, or `metrics_http`
        ("127.0.0.1:<port>": GET /health and Prometheus /metrics).
      '';
    };

    bots = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule botModule);
      default = {};
      example = lib.literalExpression ''
        { dj = { server = "rotation"; extraArgs = ["--input" "wav:/srv/music/loop.wav" "--loop"]; }; }
      '';
      description = ''
        reclaimer-bot instances, each a service (reclaimer-bot-<name>) that
        joins a server here as a member of its chat and voice only: a DJ, an
        announcer, a relay. A server takes up to 8. See BOT.md.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = let
      servers = lib.attrValues enabledServers;
      ports = map (s: s.port) servers;
      names = map (s: s.name) servers;
      metrics = lib.filter (m: m != null) (map (s: s.metrics_http or null) servers);
    in
      [
        {
          assertion = servers != [];
          message = "services.reclaimer: enable at least one server in services.reclaimer.servers.";
        }
        {
          assertion = lib.length servers <= 32;
          message = "services.reclaimer: one dedicated.toml runs at most 32 servers.";
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
          # RCON listens on TCP at the game port, and the master takes both.
          assertion = !(lib.elem cfg.settings.master.port ports);
          message = "services.reclaimer: no server may use the master's port ${toString cfg.settings.master.port}.";
        }
        {
          assertion = lib.length (lib.unique metrics) == lib.length metrics;
          message = "services.reclaimer: every server's metrics_http needs its own address.";
        }
        {
          assertion = !steamcmd || cfg.workshop.username != null;
          message = "services.reclaimer: workshop.steamcmd.enable needs workshop.username, the Steam account SteamCMD is signed in with.";
        }
        {
          assertion = config.programs.nix-ld.enable;
          message = "services.reclaimer: the servers run upstream's unpatched Linux build, which needs programs.nix-ld.enable.";
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
      servers
      ++ lib.mapAttrsToList (id: b: {
        assertion = lib.hasAttr b.server enabledServers;
        message = "services.reclaimer: bot '${id}' joins server '${b.server}', which isn't an enabled services.reclaimer.servers entry.";
      })
      enabledBots
      ++ lib.mapAttrsToList (id: b: {
        assertion = builtins.match "[A-Za-z0-9 _-]{1,15}" b.name != null;
        message = "services.reclaimer: bot '${id}' name '${b.name}' must be 1 to 15 letters, numbers, spaces, _ or -.";
      })
      enabledBots;

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

        reclaimer = {
          description = "Project Reclaimer dedicated servers";
          wantedBy = ["multi-user.target"];
          # Wants, not Requires: a Requires would pass the config unit's
          # restart on to the servers, which auto_reload makes needless. The
          # supervisor writes a default dedicated.toml when there is none, so
          # ours must be in place first.
          wants = ["network-online.target" "reclaimer-config.service"];
          after = ["network-online.target" "reclaimer-config.service"];
          inherit environment restartTriggers;
          serviceConfig =
            {
              User = cfg.user;
              Group = cfg.group;
              WorkingDirectory = cfg.dataDir;
              ExecStart = "${lib.getExe run} dedicated --config ${cfg.dataDir}/dedicated.toml";
              # Upstream's unit: the supervisor stops every server cleanly on
              # SIGINT, closes forwarded ports, and is allowed 30 seconds.
              KillSignal = "SIGINT";
              TimeoutStopSec = 30;
              Restart = "always";
              RestartSec = 5;
              EnvironmentFile = cfg.environmentFiles;
              BindReadOnlyPaths = bindReadOnlyPaths;
              BindPaths = bindPaths;
              UMask = "0027";

              # It writes only its own folders. auto_update rewrites the
              # program in homeDir, so that stays writable and exec-able.
              ProtectSystem = "strict";
              ReadWritePaths =
                [cfg.dataDir cfg.homeDir cfg.cacheDir]
                ++ lib.optional (cfg.workshop.dir != null) cfg.workshop.dir;
              ProtectHome = "read-only";
              PrivateTmp = true;
              PrivateDevices = true;
              NoNewPrivileges = true;
              ProtectKernelTunables = true;
              ProtectKernelModules = true;
              ProtectKernelLogs = true;
              ProtectControlGroups = true;
              ProtectClock = true;
              ProtectHostname = true;
              LockPersonality = true;
              RestrictRealtime = true;
              RestrictSUIDSGID = true;
              # Netlink for the interface addresses UPnP and `status` read.
              RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK"];
              # No MemoryDenyWriteExecute: the engine is translated from
              # halo3.dll at run time.
            }
            # SteamCMD runs through steam-run, a bubblewrap sandbox that needs
            # user namespaces and the capabilities it holds in them.
            // lib.optionalAttrs (!steamcmd) {
              RestrictNamespaces = true;
              CapabilityBoundingSet = "";
            }
            // cfg.serviceConfig;
        };
      }
      // lib.mapAttrs' (id: b:
        lib.nameValuePair "reclaimer-bot-${id}" {
          description = "Project Reclaimer bot ${b.name} on ${enabledServers.${b.server}.name}";
          wantedBy = ["multi-user.target"];
          after = ["reclaimer.service"];
          # A bot without the role, or banned, leaves: try again now and then.
          serviceConfig = {
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = cfg.homeDir;
            ExecStartPre = pkgs.writeShellScript "reclaimer-bot-${id}-key" ''
              key=${lib.escapeShellArg b.keyFile}
              if [ ! -e "$key" ]; then
                ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$key")"
                echo "reclaimer-bot: new identity in $key; give this player ID a role with bots.run:"
                ${lib.getExe cfg.botPackage} id --key "$key"
              fi
            '';
            ExecStart = lib.escapeShellArgs ([
                (lib.getExe cfg.botPackage)
                "join"
                "127.0.0.1:${toString enabledServers.${b.server}.port}"
                "--name"
                b.name
                "--key"
                b.keyFile
              ]
              ++ b.extraArgs);
            Restart = "always";
            RestartSec = 30;
            ProtectSystem = "strict";
            ReadWritePaths = [cfg.homeDir];
            ProtectHome = "read-only";
            PrivateTmp = true;
            PrivateDevices = true;
            NoNewPrivileges = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            RestrictNamespaces = true;
            CapabilityBoundingSet = "";
            RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
          };
        })
      enabledBots;

    users.users = lib.mkIf (cfg.user == "reclaimer") {
      reclaimer = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.homeDir;
        description = "Project Reclaimer dedicated servers";
      };
    };
    users.groups = lib.mkIf (cfg.group == "reclaimer") {reclaimer = {};};

    # The folders `dedicated init` would make; with dedicated.toml present the
    # supervisor never runs it.
    systemd.tmpfiles.rules =
      [
        "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.dataDir}/content 0750 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.dataDir}/content/Maps 0750 ${cfg.user} ${cfg.group} - -"
        "d '${cfg.dataDir}/content/Game Modes' 0750 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.dataDir}/content/Images 0750 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.dataDir}/content/Mods 0750 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.dataDir}/data 0750 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.dataDir}/playlists 0750 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.homeDir} 0750 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.cacheDir} 0750 ${cfg.user} ${cfg.group} - -"
      ]
      ++ lib.optional (cfg.gameDir == "${cfg.dataDir}/game") "d ${cfg.dataDir}/game 0750 ${cfg.user} ${cfg.group} - -";

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedUDPPorts =
        map (s: s.port) (lib.attrValues enabledServers)
        ++ lib.optional cfg.settings.master.enabled cfg.settings.master.port;
      allowedTCPPorts = lib.optional cfg.settings.master.enabled cfg.settings.master.port;
    };

    environment.systemPackages =
      [cli fetchGame]
      ++ lib.optional (cfg.modsDir != null) fetchWorkshop
      ++ lib.optional steamcmd cfg.workshop.steamcmd.package;
  };
}
