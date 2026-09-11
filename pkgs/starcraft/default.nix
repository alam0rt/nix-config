{
  lib,
  writeShellApplication,
  makeDesktopItem,
  symlinkJoin,
  wineWow64Packages,
  unzip,
  coreutils,
  # The Starcraft_1161.zip derivation from ../starcraft-1161.
  gameZip,
  # PvPGN server to pre-register as a Battle.net gateway.
  serverAddress ? "sauron",
  serverTitle ? "WankNet",
}: let
  wine = wineWow64Packages.stable;

  launcher = writeShellApplication {
    name = "starcraft";
    runtimeInputs = [wine unzip coreutils];
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

      # Battle.net gateway list. StarCraft 1.16.1 keeps it as a REG_MULTI_SZ
      # whose first element selects the active gateway and whose remaining
      # elements are (address, timezone, title) triples — the format pvpgn's
      # own "Universal Battle.net Gateway Installer" writes. Re-applied on every
      # launch so a change here takes effect without rebuilding the prefix.
      wine reg add 'HKEY_CURRENT_USER\Software\Battle.net\Configuration' \
        /v 'Battle.net Gateways' /t REG_MULTI_SZ \
        /d '1001\0${serverAddress}\01\0${serverTitle}' /f >/dev/null 2>&1

      cd "$gamedir"
      exec wine StarCraft.exe "$@"
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
