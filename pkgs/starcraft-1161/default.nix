{
  lib,
  fetchurl,
}:
# StarCraft: Brood War 1.16.1, as the BWAPI community distributes it.
#
# BWAPI requires 1.16.1 exactly: patch 1.18 added anti-cheat measures that break
# it, and Blizzard's current free download is 1.18+ with no supported downgrade,
# so the free re-release does not get you here. Blizzard's FTP still serves the
# official 1.16.1 *patches* (ftp.blizzard.com/pub/broodwar/patches/PC/BW-1161.exe)
# but those are PE wrappers around an MPQ of patched binaries and carry none of
# the game data.
#
# This is the ICCup-derived install that SSCAIT's tutorial has always pointed at,
# described there as "hosted with permission from Activision Blizzard". The host
# moved from cs.mun.ca/~dchurchill to davechurchill.ca; SSCAIT still links the
# old URL, which 404s.
fetchurl {
  name = "Starcraft_1161.zip";
  url = "https://davechurchill.ca/starcraft/files/Starcraft_1161.zip";
  hash = "sha256-G58L9bcZxZ7ERWO6Dfg0v8cIczIxXXqeZ7BzEmiukNw=";

  # Cross-checked against PvPGN's own version table before pinning: conf/
  # versioncheck.json.in expects `StarCraft.exe 01/09/09 22:57:43 1220608` for
  # SEXP revision 0xd3 (Brood War 1.16.1), and the StarCraft.exe in this zip is
  # exactly 1220608 bytes with that timestamp. Contents are at the top level —
  # StarCraft.exe, storm.dll, STARDAT.MPQ, BROODAT.MPQ, battle.snp, characters/,
  # maps/ — which is the layout both consumers expect.

  meta = {
    description = "StarCraft: Brood War 1.16.1 game files (BWAPI-compatible build)";
    homepage = "https://davechurchill.ca/starcraft/";
    # Blizzard's game data. Redistributed by the AI research community with
    # Activision Blizzard's permission, but not under any license nixpkgs can
    # express.
    license = lib.licenses.unfree;
    platforms = lib.platforms.all;
    maintainers = [];
  };
}
