{
  config,
  lib,
  pkgs,
  ...
}: let
  stateDir = "/srv/data/bwapi";

  # scbw hardcodes ~/.scbw for its data root, so HOME decides where bots, maps,
  # BWTA caches and per-game directories land.
  scbwHome = "${stateDir}/.scbw";

  # The bots the ladder plays. Every one of these is an AI_MODULE bot — a plain
  # BWAPI DLL that the game loads itself — which avoids the JAVA_MIRROR and EXE
  # bots that need a separate proxy process started in the right order. Names
  # are matched against the SSCAIT bot list (fuzzy, so exact case is not
  # critical) and downloaded on first use into ${scbwHome}/bots.
  #
  # Race spread is deliberate: a ladder of six Protoss bots produces very
  # samey games. See README.md for what each one is.
  bots = [
    "Locutus" # Protoss — the well-known UAlbertaBot descendant
    "Stardust" # Protoss
    "BananaBrain" # Protoss
    "Steamhammer" # Zerg — the other big open-source lineage
    "Crona" # Zerg
    "WillyT" # Terran
  ];

  # Rotating through the SSCAI map pack rather than always playing Benzene
  # (scbw's default) keeps build orders from being the only thing under test.
  maps = [
    "sscai/(2)Benzene.scx"
    "sscai/(2)Destination.scx"
    "sscai/(2)Heartbreak Ridge.scx"
    "sscai/(4)Andromeda.scx"
    "sscai/(4)Circuit Breaker.scx"
    "sscai/(4)Python.scx"
  ];

  # podman exposes a Docker-compatible API on this socket; the `docker` Python
  # SDK that scbw uses picks it up from DOCKER_HOST. Nothing here talks to a
  # real Docker daemon.
  podmanEnv = {
    DOCKER_HOST = "unix:///run/podman/podman.sock";
    HOME = stateDir;
  };

  # Wrapper so `scbw.play ...` works from a root shell on sauron with the same
  # environment the units use — this is how you start a human-vs-bot game.
  scbwWrapped = pkgs.writeShellScriptBin "scbw" ''
    export DOCKER_HOST=${podmanEnv.DOCKER_HOST}
    export HOME=${stateDir}
    exec ${pkgs.scbw}/bin/scbw.play "$@"
  '';

  # scbw as an importable library, not just a CLI. Resolving a bot needs its
  # code: bwapi_version is derived from the md5 of the bot's BWAPI.dll matched
  # against a known-versions table, and the SSCAIT downloader handles the
  # fuzzy name matching. Reimplementing either would be a second source of truth.
  scbwPython = pkgs.python3.withPackages (ps: [(ps.toPythonModule pkgs.scbw)]);

  resolveBot = pkgs.writeTextFile {
    name = "resolve-bot.py";
    text = ''
      """Print shell-evalable metadata for a bot, downloading it if needed."""
      import shlex
      import sys

      from scbw.bot_storage import LocalBotStorage, SscaitBotStorage

      bot_dir, name = sys.argv[1], sys.argv[2]
      bot = LocalBotStorage(bot_dir).find_bot(name) or SscaitBotStorage(bot_dir).find_bot(name)
      if bot is None:
          sys.exit(f"no bot matching {name!r}")

      for key, value in [
          ("BOT_NAME", bot.name),
          ("BOT_FILE", bot.bot_basefilename),
          ("BOT_BWAPI", bot.bwapi_version),
          ("BOT_RACE", bot.race.value),
          ("BOT_PATH", bot.bot_dir),
      ]:
          print(f"{key}={shlex.quote(str(value))}")
    '';
  };

  # Play a human on another machine. The bot joins a game that StarCraft on the
  # far end is hosting, over LAN/UDP — not over PvPGN, which BWAPI cannot use
  # (see README.md). bwheadless --lan-sendto hooks ws2_32!sendto and rewrites
  # every outgoing destination to the given address, so the bot unicasts to the
  # player instead of broadcasting, and the player's client replies to the
  # container's source address. That is what makes this work across the tailnet,
  # which has no broadcast domain.
  joinScript = pkgs.writeShellApplication {
    name = "bwapi-join";
    runtimeInputs = [pkgs.podman pkgs.coreutils scbwPython];
    text = ''
      bot=""; sendto=""; game="vs-bot"; race=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --bot)    bot="$2"; shift 2 ;;
          --sendto) sendto="$2"; shift 2 ;;
          --game)   game="$2"; shift 2 ;;
          --race)   race="$2"; shift 2 ;;
          *) echo "unknown argument: $1" >&2; exit 2 ;;
        esac
      done
      [ -n "$bot" ] || { echo "--bot is required" >&2; exit 2; }
      [ -n "$sendto" ] || { echo "--sendto <player ip> is required" >&2; exit 2; }

      export HOME=${stateDir}
      bots="${scbwHome}/bots"

      # Downloads from SSCAIT on first use, same store the ladder populates.
      eval "$(python3 ${resolveBot} "$bots" "$bot")"
      [ -n "''${race}" ] || race="$BOT_RACE"

      echo "$BOT_NAME ($race) joining game '$game' hosted at $sendto"

      rundir="${scbwHome}/games/$game"
      mkdir -p "$rundir"/{logs,write,errors}

      # --network host, not scbw's sc_net bridge: the bridge SNATs, which breaks
      # the return path from the player's client back into the container.
      exec podman run --rm --network host \
        --name "bwapi-join-$game" \
        -e PLAYER_NAME="$BOT_NAME" \
        -e PLAYER_RACE="$race" \
        -e NTH_PLAYER=1 \
        -e NUM_PLAYERS=2 \
        -e GAME_NAME="$game" \
        -e MAP_NAME=/app/sc/maps/sscai/'(2)Benzene.scx' \
        -e GAME_TYPE=MELEE \
        -e SPEED_OVERRIDE=0 \
        -e SEED_OVERRIDE=0 \
        -e HIDE_NAMES=0 \
        -e DROP_PLAYERS=1 \
        -e BOT_FILE="$BOT_FILE" \
        -e BOT_BWAPI="$BOT_BWAPI" \
        -e TM_LOG_RESULTS=../logs/scores.json \
        -e TM_LOG_FRAMETIMES=../logs/frames.csv \
        -e TM_LOG_UNIT_EVENTS=../logs/unit_events.csv \
        -e TM_SPEED_OVERRIDE=0 \
        -e TM_SEED_OVERRIDE=0 \
        -e TM_ALLOW_USER_INPUT=0 \
        -e TM_TIME_OUT_AT_FRAME=-1 \
        -e EXIT_CODE_REALTIME_OUTED=2 \
        -e CAPTURE_MOUSE_MOVEMENT=0 \
        -e HEADFUL_AUTO_LAUNCH=0 \
        -e JAVA_DEBUG=0 \
        -e JAVA_DEBUG_PORT="" \
        -e JAVA_OPTS="" \
        -v "$rundir/logs":/app/logs:rw \
        -v "$rundir/write":/app/sc/bwapi-data/write:rw \
        -v "$rundir/errors":/app/sc/Errors:rw \
        -v "$BOT_PATH":/app/bot:ro \
        -v "${scbwHome}/maps":/app/sc/maps:rw \
        -v "${scbwHome}/bwapi-data/BWTA":/app/sc/bwapi-data/BWTA:rw \
        -v "${scbwHome}/bwapi-data/BWTA2":/app/sc/bwapi-data/BWTA2:rw \
        starcraft:game \
        /app/play_bot.sh \
          --game "$game" --name "$BOT_NAME" --race "$race" \
          --lan --join --lan-sendto "$sendto"
    '';
  };

  ladderScript = pkgs.writeShellApplication {
    name = "bwapi-ladder-run";
    runtimeInputs = [pkgs.scbw pkgs.coreutils];
    text = ''
      export DOCKER_HOST=${podmanEnv.DOCKER_HOST}
      export HOME=${stateDir}

      mapfile -t picked < <(printf '%s\n' ${lib.escapeShellArgs bots} | shuf -n 2)
      map=$(printf '%s\n' ${lib.escapeShellArgs maps} | shuf -n 1)

      echo "match: ''${picked[0]} vs ''${picked[1]} on $map"

      # --headless skips Xvfb/x11vnc entirely; nothing is watching. --timeout
      # caps a game at 30 minutes of wall clock, because a bot that deadlocks
      # will otherwise sit in a container forever and the timer will pile up
      # another game on top of it.
      exec scbw.play \
        --headless \
        --bots "''${picked[0]}" "''${picked[1]}" \
        --map "$map" \
        --timeout 1800 \
        --game_speed 0 \
        --read_overwrite \
        --log_level INFO
    '';
  };
in {
  # scbw drives containers over the Docker-compatible API rather than shelling
  # out to `podman`, so podman.socket has to actually be listening — this option
  # is what enables it. dockerCompat in ../configuration.nix only provides the
  # `docker` CLI alias, which is a different thing entirely.
  virtualisation.podman.dockerSocket.enable = true;

  systemd.tmpfiles.rules = [
    "d ${stateDir}        0750 root root - -"
    "d ${scbwHome}        0750 root root - -"
    "d ${scbwHome}/bots   0750 root root - -"
    "d ${scbwHome}/maps   0750 root root - -"
    "d ${scbwHome}/games  0750 root root - -"
  ];

  # One-time image bootstrap, converged on every switch. The game comes from
  # the store via pkgs/starcraft-1161, so there is nothing to place by hand —
  # unlike sc-docker's own flow, which fetches it from files.theabyss.ru and
  # has been broken since that mirror died.
  systemd.services.bwapi-images = {
    description = "Build the StarCraft/BWAPI container image for scbw";
    wantedBy = ["multi-user.target"];
    after = ["podman.socket" "network-online.target"];
    wants = ["podman.socket" "network-online.target"];
    path = [pkgs.podman pkgs.coreutils];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      if podman image exists starcraft:game; then
        echo "starcraft:game already built, nothing to do"
        exit 0
      fi

      # The base layers (Wine, BWAPI, bwheadless, the tournament modules) come
      # from the images the SSCAIT group published in 2018. Rebuilding them from
      # sc-docker's own dockerfiles is not an option: they are FROM ubuntu:xenial
      # and apt-get update against an EOL release fails.
      if ! podman image exists starcraft:java; then
        podman pull docker.io/ggaic/starcraft:java
        podman tag docker.io/ggaic/starcraft:java starcraft:java
      fi

      # game.dockerfile is the only layer that has to be built here: it unpacks
      # the game over the base image and writes the Blizzard registry keys.
      ctx=$(mktemp -d)
      trap 'rm -rf "$ctx"' EXIT
      cp ${pkgs.scbw.gameDockerContext}/* "$ctx"/
      cp ${pkgs.starcraft-1161} "$ctx"/starcraft.zip
      podman build -f "$ctx"/game.dockerfile -t starcraft:game "$ctx"
    '';
  };

  # Downloads the SSCAI map pack and the precomputed BWTA terrain-analysis
  # caches. Without the caches every bot spends the first minute of every game
  # re-analysing the map, which makes short test games useless.
  systemd.services.bwapi-install = {
    description = "Fetch scbw maps and BWTA caches";
    wantedBy = ["multi-user.target"];
    after = ["bwapi-images.service"];
    requires = ["bwapi-images.service"];
    environment = podmanEnv;

    unitConfig.ConditionPathExists = "!${scbwHome}/maps/sscai";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.scbw}/bin/scbw.play --install";
    };
  };

  # The ladder itself: one game per firing, two bots picked at random.
  systemd.services.bwapi-ladder = {
    description = "Play one headless BWAPI bot-vs-bot game";
    after = ["bwapi-install.service"];
    requires = ["bwapi-install.service"];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe ladderScript;

      # A game is two Wine containers each running a full StarCraft; on a box
      # that is also transcoding and serving media, keep them off the cores
      # that matter.
      CPUWeight = 20;
      IOWeight = 20;
    };
  };

  systemd.timers.bwapi-ladder = {
    description = "Run a BWAPI bot game periodically";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      RandomizedDelaySec = "10m";
      Persistent = false;
      AccuracySec = "1m";
    };
  };

  environment.systemPackages = [scbwWrapped joinScript];

  # The laptop's `sc-vs` runs this over SSH, where an interactive password
  # prompt is not available. Scoped to this one wrapper rather than opening up
  # podman or systemctl: it takes four arguments, all of which end up as
  # container env, and the worst it can do is start a StarCraft container.
  security.sudo.extraRules = [
    {
      groups = ["wheel"];
      commands = [
        {
          command = "${lib.getExe joinScript}";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];
}
