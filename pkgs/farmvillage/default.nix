{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchzip,
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

  # Ruffle self-hosted web bundle (WASM Flash emulator) so the AS3 game can run
  # in modern browsers without the dead Adobe plugin. Pinned nightly.
  ruffle = fetchzip {
    url = "https://github.com/ruffle-rs/ruffle/releases/download/nightly-2026-06-26/ruffle-nightly-2026_06_26-web-selfhosted.zip";
    hash = "sha256-mGX4FusQ2ReV07JHdqBROxYhoiZqN6FosIJxkplk/Lc=";
    stripRoot = false;
  };
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

    # Patches:
    # 1. Decouple writable data dirs (saves/assets/cache/tmp) from the read-only
    #    store, and make the client-facing base_url overridable, both via env vars.
    # 2. Serve the vendored Ruffle bundle at /ruffle/ and inject its loader into
    #    play.html so the game plays via WASM in modern browsers.
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

      # Upstream hardcodes Windows path separators here, which breaks on Linux
      # (backslashes are literal filename chars). Use proper os.path.join segments.
      substituteInPlace game_settings.py \
        --replace-fail 'os.path.join(XML_DIR, "gz\\v855098\\gameSettings.xml.gz")' \
          'os.path.join(XML_DIR, "gz", "v855098", "gameSettings.xml.gz")'

      substituteInPlace server.py \
        --replace-fail 'app: Flask = Flask(__name__)' \
          'app: Flask = Flask(__name__)
import logging as _logging
_FV_DEBUG = bool(os.environ.get("FARMVILLAGE_DEBUG"))
_logging.basicConfig(level=_logging.DEBUG if _FV_DEBUG else _logging.INFO,
                     format="%(asctime)s %(levelname)s %(name)s: %(message)s")
_logging.getLogger("werkzeug").setLevel(_logging.INFO)' \
        --replace-fail '    # print("[+] Gateway AMF3 Request:", resp_msg)' \
          '    if _FV_DEBUG: print("[+] Gateway AMF3 Request:", resp_msg)' \
        --replace-fail '    reqs = resp_msg.bodies[0][1].body[1]' \
          '    reqs = resp_msg.bodies[0][1].body[1]
    if isinstance(reqs, dict):  # py3amf >=0.8.11 decodes the batch as {0: ...} instead of a list
        reqs = list(reqs.values())' \
        --replace-fail 'base_url=f"http://{BIND_IP}:{BIND_PORT}",' \
          'base_url=os.environ.get("FARMVILLAGE_BASE_URL", f"http://{BIND_IP}:{BIND_PORT}"),' \
        --replace-fail '@app.route("/crossdomain.xml", methods=['"'"'GET'"'"'])' \
          '@app.route("/ruffle/<path:path>", methods=['"'"'GET'"'"'])
def ruffle(path):
    return send_from_directory(os.path.join(TEMPLATES_DIR, "ruffle"), path)

@app.route("/masterysigns/<path:path>", methods=['"'"'GET'"'"'])
def masterysigns(path):
    # Upstream serves no mastery-sign data; return a valid empty gzipped AMF3
    # object so the client gets 200 instead of a 404 URLLoader error. The game
    # rejects a bare array ("Invalid object") in its load-complete handler, so
    # encode an (empty) object/dict.
    import io, gzip
    from pyamf import amf3
    buf = io.BytesIO()
    amf3.Encoder(buf).writeElement({})
    return Response(gzip.compress(buf.getvalue()), mimetype="application/x-amf")

@app.route("/crossdomain.xml", methods=['"'"'GET'"'"'])'

      substituteInPlace templates/play.html \
        --replace-fail '    </head>' \
          '        <!-- Ruffle (WASM Flash emulator) for modern browsers -->
        <script>
            window.RufflePlayer = window.RufflePlayer || {};
            window.RufflePlayer.config = {
                publicPath: "{{ base_url }}/ruffle/",
                polyfills: true,
                autoplay: "on",
                unmuteOverlay: "hidden",
                networkingAccessMode: "all",
                allowScriptAccess: true,
                warnOnUnsupportedContent: false,
                logLevel: "info",
                // FarmVille does heavy synchronous work during load (parsing
                // items_opt.amf, building the world); raise Ruffle'"'"'s runaway-script
                // limit well above the 15s default so it isn'"'"'t killed mid-load.
                maxExecutionDuration: 300,
            };
        </script>
        <script src="{{ base_url }}/ruffle/ruffle.js"></script>
    </head>' \
        --replace-fail 'src="embeds/Flash/v855097-855094/FV_Preloader.swf?swfLocation=embeds/Flash/v855097-855094/FarmGame.swf"' \
          'src="embeds/Flash/v855097-855094/FarmGame.swf"'
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/farmvillage
      cp -r . $out/share/farmvillage
      cp -r ${ruffle} $out/share/farmvillage/templates/ruffle

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
