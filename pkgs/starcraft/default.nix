{
  lib,
  writeShellApplication,
  makeDesktopItem,
  symlinkJoin,
  wineWow64Packages,
  gamescope,
  unzip,
  coreutils,
  gnugrep,
  # The Starcraft_1161.zip derivation from ../starcraft-1161.
  gameZip,
  # PvPGN server to pre-register as a Battle.net gateway.
  serverAddress ? "sauron",
  serverTitle ? "WankNet",
  # native | desktop | gamescope — see the case statement below.
  defaultDisplay ? "native",
}: let
  wine = wineWow64Packages.stable;

  launcher = writeShellApplication {
    name = "starcraft";
    # niri/wlr-randr are looked up on the inherited PATH rather than pinned:
    # they are whatever compositor the user is actually running, and the
    # resolution probe falls back to 1920x1080 if neither answers.
    runtimeInputs = [wine unzip coreutils gamescope gnugrep];
    text = ''
      prefix="''${XDG_DATA_HOME:-$HOME/.local/share}/starcraft"
      gamedir="$prefix/game"

      # StarCraft writes to its own directory — saved games, replays, downloaded
      # maps, the CD-key — so the read-only store copy is unpacked into $HOME
      # once rather than run in place.
      export WINEPREFIX="$prefix/wine"

      # No WINEARCH: wineWow64Packages is the new-wow64 build, which has only
      # 64-bit prefixes and runs the 32-bit StarCraft.exe through WoW64.
      # (wineWowPackages, which does support WINEARCH=win32, is deprecated
      # upstream and warns on every evaluation.) If the game misbehaves in ways
      # that smell like thunking — DirectDraw surfaces, sound init — a real
      # 32-bit prefix is the fallback: pkgsi686Linux.wine with WINEARCH=win32.

      # Suppress the Mono and Gecko installer prompts on first run; StarCraft
      # needs neither.
      export WINEDLLOVERRIDES="mscoree,mshtml="

      if [ ! -f "$gamedir/StarCraft.exe" ]; then
        echo "unpacking StarCraft 1.16.1 into $gamedir (first run only)"
        mkdir -p "$gamedir"
        unzip -q -o ${gameZip} -d "$gamedir"
      fi

      if [ ! -d "$WINEPREFIX" ]; then
        echo "creating wine prefix in $WINEPREFIX (first run only)"
        wineboot -u >/dev/null 2>&1
      fi

      # Battle.net gateway list, as a REG_MULTI_SZ. The format is pvpgn's own
      # "Universal Battle.net Gateway Installer" format, and the header is TWO
      # elements, not one: a literal "1001" and a zero-padded index selecting
      # the active gateway. Its :selectserver does `set str=!str:~8!` — strip
      # exactly the 8 characters of "1001\000" — then re-emits
      # `1001\0<NN><rest>`. Gateways follow as (address, timezone, title)
      # triples.
      #
      # Getting this wrong is silent: with the index element missing, StarCraft
      # reads the address as the index and then hits a truncated triple, and
      # shows an entirely empty gateway list rather than any error.
      #
      # The separator is given explicitly with /s rather than relying on
      # reg.exe's default. Wine's reg.exe mangles the literal "\0" form: passing
      # /d '1001\0sauron\01\0WankNet' stored "1001", "0001uron", "1", "WankNet",
      # which StarCraft could not parse at all — it showed an empty gateway list.
      # With /s '|' it round-trips correctly.
      #
      # Written unconditionally on every launch, which is idempotent by
      # construction — the same value each time — and self-healing if the key
      # is ever left malformed. The cost is that an in-game gateway selection
      # does not survive a relaunch, which is moot with a single gateway.
      wine reg add 'HKEY_CURRENT_USER\Software\Battle.net\Configuration' \
        /v 'Battle.net Gateways' /t REG_MULTI_SZ /s '|' \
        /d '1001|01|${serverAddress}|1|${serverTitle}' /f >/dev/null 2>&1

      cd "$gamedir"

      # StarCraft is a fixed 640x480 DirectDraw game with no windowed mode of its
      # own, so "windowed" has to come from outside it.
      #
      #   native    (default) real fullscreen; the game changes the display mode
      #   desktop   a Wine virtual desktop — a plain window, no mode change, but
      #             only as large as the game's own 640x480
      #   gamescope a nested compositor that upscales 640x480 to the whole
      #             screen; this is the "fullscreen windowed" one
      #
      # Override per launch: SC_DISPLAY=gamescope starcraft
      case "''${SC_DISPLAY:-${defaultDisplay}}" in
        gamescope)
          # -w/-h are the game's own resolution, -f fullscreen. gamescope takes
          # the 640x480 output and scales it to the display, which is the whole
          # point: without it StarCraft renders 640x480 into the middle of the
          # screen and leaves the rest black, because under XWayland the
          # DirectDraw mode change does not resize the actual output.
          #
          # scaler "fit" fills as much of the screen as 4:3 allows (1440x1080 on
          # a 1080p panel) and pillarboxes the rest. "integer" is sharper — whole
          # pixels, 2x to 1280x960 — but noticeably smaller. Try both:
          #   SC_SCALER=integer SC_FILTER=nearest starcraft
          # -W/-H (output size) are not optional. Without them gamescope sizes
          # its output to -w/-h, i.e. to the game's own 640x480, and there is
          # nothing left to scale into — the log gives it away with
          # "edid: Patching res <native> -> 640x480".
          res="''${SC_OUTPUT:-}"
          if [ -z "$res" ]; then
            res=$(niri msg outputs 2>/dev/null \
              | grep -m1 -oE 'Current mode: [0-9]+x[0-9]+' \
              | grep -oE '[0-9]+x[0-9]+' || true)
          fi
          if [ -z "$res" ]; then
            res=$(wlr-randr 2>/dev/null \
              | grep -m1 -oE '[0-9]+x[0-9]+ px' \
              | grep -oE '[0-9]+x[0-9]+' || true)
          fi
          res="''${res:-1920x1080}"

          exec gamescope \
            -w 640 -h 480 \
            -W "''${res%x*}" -H "''${res#*x}" \
            -S "''${SC_SCALER:-fit}" \
            -F "''${SC_FILTER:-linear}" \
            -f -- wine StarCraft.exe "$@"
          ;;
        desktop)
          exec wine explorer /desktop=StarCraft,640x480 StarCraft.exe "$@"
          ;;
        *)
          exec wine StarCraft.exe "$@"
          ;;
      esac
    '';
  };

  desktopItem = makeDesktopItem {
    name = "starcraft";
    desktopName = "StarCraft: Brood War";
    comment = "StarCraft 1.16.1 under Wine, pointed at ${serverTitle}";
    exec = "starcraft";
    categories = ["Game" "StrategyGame"];
    terminal = false;
  };
in
  symlinkJoin {
    name = "starcraft-1161-wine";
    paths = [launcher desktopItem];
    meta = {
      description = "StarCraft: Brood War 1.16.1 launcher (Wine), preconfigured for a PvPGN gateway";
      mainProgram = "starcraft";
      license = lib.licenses.unfree;
      platforms = lib.platforms.linux;
      maintainers = [];
    };
  }
