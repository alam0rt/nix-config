{
  stdenv,
  lib,
  python3Packages,
  fetchFromGitHub,
  ffmpeg-headless,
  makeWrapper,
  fetchNpmDeps,
}:
let 
  buildPython = python3Packages.python.withPackages (ps: [ ps.jinja2 ]);
in
  stdenv.mkDerivation rec {
    pname = "propagandabot";
    version = "v6.5-0";
    src = fetchFromGitHub {
      owner = "ult1m4";
      repo = "PropagandaBot";
      rev = "4255d5c6e8d9822bcb37b27af45e5e4ee9639494";
      sha256 = "XaS9rjDnPpYjBJX0jCiqr588JMyLA+S+ul+3fiyNhHA=";
    };
    vendorHash = "sha256-QcGAnfjcka5JxLm/3NAeswAPohCNEUrWCLvajs2lLyw=";

    patches = [
      ./debug.patch
    ];

    pythonPath = with python3Packages; [
      pymumble
      yt-dlp
      packaging
      mutagen
      python-magic
      pillow
      pyradios
      flask
    ];

    nativeBuildInputs = [
      makeWrapper
      python3Packages.wrapPython
    ];

    NODE_OPTIONS = "--openssl-legacy-provider";

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share $out/bin
      cp -r . $out/share/botamusique
      chmod +x $out/share/botamusique/mumbleBot.py
      wrapPythonProgramsIn $out/share/botamusique "$out $pythonPath"

      # Convenience binary and wrap with ffmpeg dependency
      makeWrapper $out/share/botamusique/mumbleBot.py $out/bin/botamusique \
        --prefix PATH : ${lib.makeBinPath [ ffmpeg-headless ]}

      runHook postInstall
    '';

    postPatch = ''
      # However, the function that's patched above is also used for
      # configuration.default.ini, which is in the installation directory
      # after all. So we need to counter-patch it here so it can find it absolutely
      substituteInPlace mumbleBot.py \
        --replace "configuration.default.ini" "$out/share/botamusique/configuration.default.ini" \
        --replace "version = 'git'" "version = '${version}'"
    '';

    meta = {
      description = "Fork of Botamusique to support YT-DLP and modern stream functionality. Intended to be static, with manual updates to YT-DLP.";
      license = lib.licenses.mit;
      homepage = "https://github.com/${src.owner}/${src.repo}";
    };
  }
