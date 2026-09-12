{
  lib,
  python3Packages,
  fetchFromGitHub,
}:
python3Packages.buildPythonApplication rec {
  pname = "scbw";

  # basil-ladder's fork rather than the original Games-and-Simulations tree:
  # same code, but it is the one BASIL (the StarCraft AI ladder) actually runs
  # and it is four years newer. Upstream's last commit is 2023.
  version = "1.1.0-unstable-2025-07-16";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "basil-ladder";
    repo = "sc-docker";
    rev = "2d90f532f5772a874163f6986cd5b850fe7c5857";
    hash = "sha256-kLsAbbvPEyb0DWVXbWfZWI5T4DrJMFV7lcJrz48MaUs=";
  };

  # docker_utils.py imports distutils, which was removed from the standard
  # library in Python 3.12. Only `copy_tree` is actually called — to merge each
  # bot's per-game `write_N` output back over its persistent read directory —
  # and shutil.copytree with dirs_exist_ok=True (Python 3.8+) has the same
  # semantics for that use. `distutils.errors` is imported but never referenced.
  postPatch = ''
        substituteInPlace scbw/docker_utils.py \
          --replace-fail 'import distutils.dir_util
    import distutils.errors' 'import shutil' \
          --replace-fail 'distutils.dir_util.copy_tree(
                        f"{game_dir}/{game_name}/write_{nth_player}",
                        player.read_dir
                    )' 'shutil.copytree(
                        f"{game_dir}/{game_name}/write_{nth_player}",
                        player.read_dir,
                        dirs_exist_ok=True,
                    )'
  '';

  propagatedBuildInputs = with python3Packages; [
    requests
    coloredlogs
    numpy
    tqdm
    python-dateutil
    pandas
    matplotlib
    docker
  ];

  # No test suite in the tree beyond bats-based integration tests that need a
  # working Docker daemon and the StarCraft image, neither of which exists in
  # the sandbox.
  doCheck = false;

  pythonImportsCheck = ["scbw"];

  # The module needs scbw/local_docker/{game.dockerfile,player.spc,player.mpc}
  # as a build context for the one image that has to be built locally. They are
  # in package_data, but referencing the unpacked source directly is clearer
  # than digging them out of site-packages.
  passthru.gameDockerContext = "${src}/scbw/local_docker";

  # Tournament-module DLLs, one per BWAPI version. play_bot.sh does
  # `cp $TM_DIR/$BOT_BWAPI.dll` and dies under `set -e` if the version it wants
  # is missing — which is what happens with the 2018 base image, whose spec
  # lists only BWAPI 3.7.4, 3.7.5, 4.1.2 and 4.2.0 while every current SSCAIT
  # bot is 4.4.0.
  passthru.tmModules = "${src}/docker/tm";

  # Build context for the wine/bwapi/play/java image chain. Everything those
  # dockerfiles COPY is relative to this directory.
  passthru.dockerContext = "${src}/docker";

  meta = {
    description = "Launcher for StarCraft: Brood War BWAPI bot games in Docker containers";
    homepage = "https://github.com/basil-ladder/sc-docker";
    license = lib.licenses.mit;
    mainProgram = "scbw.play";
    platforms = lib.platforms.linux;
    maintainers = [];
  };
}
