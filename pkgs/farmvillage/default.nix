{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  python3,
  makeWrapper,
}: let
  pythonEnv = python3.withPackages (ps:
    with ps; [
      flask
      requests
      tqdm
      xmltodict
      py3amf
    ]);
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "farmvillage";
    version = "0-unstable-2025-02-23";

    src = fetchFromGitHub {
      owner = "AcidCaos";
      repo = "farmvillage";
      rev = "b3d3d782945af3754cadefbbbc60ee475c1dc811";
      hash = "sha256-Nl4MFk+mg5H3zVxeskf4FQrOX/5pfc+cCpwv88oxbNQ=";
    };

    nativeBuildInputs = [makeWrapper];

    # Decouple writable data dirs (saves/assets/cache/tmp) from the read-only
    # store, and make the client-facing base_url overridable, both via env vars.
    postPatch = ''
      substituteInPlace bundle.py \
        --replace-fail 'SAVES_DIR = os.path.join(BASE_DIR, "saves")' \
          'DATA_DIR = os.environ.get("FARMVILLAGE_DATA_DIR", BASE_DIR)
SAVES_DIR = os.path.join(DATA_DIR, "saves")' \
        --replace-fail 'ASSETS_DIR = os.path.join(BASE_DIR, "assets")' \
          'ASSETS_DIR = os.path.join(DATA_DIR, "assets")' \
        --replace-fail 'CACHE_DIR = os.path.join(BASE_DIR, "cache")' \
          'CACHE_DIR = os.path.join(DATA_DIR, "cache")' \
        --replace-fail 'TMP_DIR = os.path.join(BASE_DIR, "tmp")' \
          'TMP_DIR = os.path.join(DATA_DIR, "tmp")'

      substituteInPlace server.py \
        --replace-fail 'base_url=f"http://{BIND_IP}:{BIND_PORT}",' \
          'base_url=os.environ.get("FARMVILLAGE_BASE_URL", f"http://{BIND_IP}:{BIND_PORT}"),'
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/farmvillage
      cp -r . $out/share/farmvillage

      makeWrapper ${pythonEnv}/bin/python $out/bin/farmvillage \
        --add-flags "$out/share/farmvillage/server.py"

      runHook postInstall
    '';

    meta = {
      description = "FarmVille 1 preservation server (AcidCaos/farmvillage)";
      homepage = "https://github.com/AcidCaos/farmvillage";
      license = lib.licenses.gpl3Only;
      mainProgram = "farmvillage";
      platforms = lib.platforms.linux;
    };
  })
