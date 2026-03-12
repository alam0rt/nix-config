{ lib
, stdenv
, fetchFromGitHub
, buildNpmPackage
, basePackage
}:

let
  # Build the Matrix plugin for OpenClaw from the same source as the gateway
  openclaw-matrix-plugin = buildNpmPackage rec {
    pname = "openclaw-matrix";
    version = basePackage.version;

    src = fetchFromGitHub {
      owner = "openclaw";
      repo = "openclaw";
      rev = basePackage.passthru.pinnedRev;
      hash = basePackage.passthru.sourceInfo.hash;
    };

    sourceRoot = "source/extensions/matrix";

    # This will fail on first build - Nix will tell us the correct hash
    npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

    dontNpmBuild = true;

    installPhase = ''
      runHook preInstall
      
      mkdir -p $out/lib/node_modules/@openclaw/matrix
      cp -r . $out/lib/node_modules/@openclaw/matrix/
      
      runHook postInstall
    '';

    meta = with lib; {
      description = "Matrix channel plugin for OpenClaw";
      homepage = "https://github.com/openclaw/openclaw";
      license = licenses.mit;
    };
  };
in
basePackage.overrideAttrs (oldAttrs: {
  postInstall = (oldAttrs.postInstall or "") + ''
    # Add the Matrix plugin to make it available to openclaw-gateway
    # Normally installed via: openclaw plugins install @openclaw/matrix
    
    echo "Installing Matrix plugin..."
    
    mkdir -p "$out/lib/openclaw/node_modules/@openclaw"
    if [ ! -e "$out/lib/openclaw/node_modules/@openclaw/matrix" ]; then
      ln -s "${openclaw-matrix-plugin}/lib/node_modules/@openclaw/matrix" \
            "$out/lib/openclaw/node_modules/@openclaw/matrix"
      echo "Matrix plugin installed"
    fi
  '';
})
