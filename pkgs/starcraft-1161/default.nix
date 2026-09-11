# Blizzard's game data, present only because the operator already has a copy.
# This repo never fetches it, never substitutes it and never redistributes it:
# requireFile only ever reads a file you added to the store yourself.
{
  requireFile,
  # sha256 of your own Starcraft_1161.zip. There is no default: the file is not
  # redistributable, so the hash depends on which copy you have. See the message
  # below, and nixos/sauron/bwapi/default.nix for where this gets set.
  hash,
}:
requireFile {
  name = "Starcraft_1161.zip";
  sha256 = hash;

  # Recorded for provenance only — requireFile never fetches. This is the URL
  # SSCAIT's tutorial still points at, described there as "hosted with
  # permission from Activision Blizzard". It 404s as of 2026-09-12: Dave
  # Churchill's pages moved from cs.mun.ca to davechurchill.ca and the files/
  # directory did not survive the move.
  url = "http://www.cs.mun.ca/~dchurchill/starcraftaicomp/files/Starcraft_1161.zip";

  message = ''
    BWAPI requires StarCraft: Brood War *1.16.1* specifically. Patch 1.18 added
    anti-cheat measures that break BWAPI, and Blizzard's current free download
    is 1.18+ with no supported way to downgrade — so the free re-release does
    not get you there on its own.

    What is still live, from Blizzard directly:

      http://ftp.blizzard.com/pub/broodwar/patches/PC/BW-1161.exe   (26.5 MB)
      http://ftp.blizzard.com/pub/starcraft/patches/PC/SC-1161.exe  (10.7 MB)

    Those are patches, not installs: a PE wrapper around an MPQ holding the
    1.16.1 binaries. They update an existing copy of the game, and carry none of
    the ~500 MB of art and sound data.

    So the zip has to be assembled from a copy of the game you have: a directory
    containing StarCraft.exe, storm.dll, StarDat.mpq, BrooDat.mpq and
    patch_rt.mpq at its root, patched to 1.16.1, zipped with those files at the
    top level (not inside a wrapper directory).

    Then add it to the store and record the hash:

      sha256sum Starcraft_1161.zip
      nix-store --add-fixed sha256 Starcraft_1161.zip

    and set that hash as `gameHash` in nixos/sauron/bwapi/default.nix.
  '';
}
