{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  zlib,
  sqlite,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "pvpgn-server";

  # Pinned to master, not to a release tag. The newest tag, 1.99.8.0.0-rc1-PRO,
  # is from November 2021 and the newest *release*, 1.99.7.2.1, is from 2018 —
  # both predate the compiler-compatibility work on master, and the 2018 tree is
  # what the old `pvpgnix` flake input built. Upstream is still committing
  # (this rev is 2026-08-08), so master is the version most likely to compile
  # against a current nixpkgs toolchain.
  version = "0-unstable-2026-08-08";

  src = fetchFromGitHub {
    owner = "pvpgn";
    repo = "pvpgn-server";
    rev = "9cd173f4e02ba3d9f8f15a67ca308b5eb78723e4";
    hash = "sha256-a7EK/6bWk+bh+Lbnb24g12XmtZQnrMhQxC78u1buxPw=";
  };

  nativeBuildInputs = [cmake];
  buildInputs = [zlib sqlite];

  cmakeFlags = [
    # SQLite is the only storage backend we want: one file under the state dir,
    # no database server to run alongside bnetd for a handful of accounts.
    (lib.cmakeBool "WITH_SQLITE3" true)
    (lib.cmakeBool "WITH_BNETD" true)

    # d2cs/d2dbs are the Diablo II realm and character-database daemons. sauron
    # only serves StarCraft/Brood War, and building them would add two more
    # binaries and a charsave directory layout that nothing here uses. Flip
    # these back on (and add the matching systemd units) if D2 is ever wanted.
    (lib.cmakeBool "WITH_D2CS" false)
    (lib.cmakeBool "WITH_D2DBS" false)

    # Lua scripting wants Lua 5.1 specifically — upstream's luawrapper uses
    # LUA_GLOBALSINDEX, which 5.2 removed. Leaving it off avoids pinning an EOL
    # Lua just for server-side event hooks we do not use.
    (lib.cmakeBool "WITH_LUA" false)

    # CMakeLists.txt declares `cmake_minimum_required(VERSION 3.1.0)`. CMake
    # 3.31+ warns on a minimum below 3.5 and CMake 4 refuses outright; this
    # tells it to treat the project as if it had asked for 3.5. Drop once
    # upstream raises its own minimum.
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  ];

  # Installs into:
  #   $out/sbin/{bnetd,bnbot,bnchat,...}
  #   $out/etc/pvpgn/          *.conf, versioncheck.json, i18n/
  #   $out/var/pvpgn/files/    icons.bni, *.mpq, newbie.save — read-only at runtime
  #   $out/var/pvpgn/{users,clans,teams,...}  empty dirs, unused with SQLite storage
  #
  # Deliberately no postInstall rewriting of paths inside the shipped confs (the
  # old pvpgnix derivation sed'd /nix/store/... into /srv/data). The NixOS module
  # generates bnetd.conf itself and every path in it is absolute, so the shipped
  # copy is only ever used as a source of the non-path config files.

  meta = {
    description = "Battle.net server emulator for classic Blizzard and Westwood Online clients";
    homepage = "https://github.com/pvpgn/pvpgn-server";
    license = lib.licenses.gpl2Plus;
    mainProgram = "bnetd";
    platforms = lib.platforms.linux;
    maintainers = [];
  };
})
