{ lib
, stdenv
, makeWrapper
, nodejs_22
, pnpm_10
, fetchurl
, basePackage
}:

let
  # Fetch the Matrix plugin tarball (fixed-output derivation with network access)
  matrixPluginTarball = fetchurl {
    url = "https://registry.npmjs.org/@openclaw/matrix/-/matrix-2026.3.11.tgz";
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

in stdenv.mkDerivation {
  pname = "${basePackage.pname}-with-matrix";
  version = basePackage.version;

  dontUnpack = true;
  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper nodejs_22 pnpm_10 ];

  # Allow network access to fetch dependencies
  __noChroot = true;

  installPhase = ''
    # Copy the base package
    cp -r ${basePackage} $out
    chmod -R +w $out

    # Set up environment for openclaw plugins install
    export HOME=$(mktemp -d)
    export PATH="$out/bin:${nodejs_22}/bin:${pnpm_10}/bin:$PATH"
    export OPENCLAW_STATE_DIR="$HOME/.openclaw"
    mkdir -p "$OPENCLAW_STATE_DIR"
    
    # Run openclaw plugins install to install the Matrix plugin
    # This uses the openclaw binary which handles plugin installation properly
    echo "Installing Matrix plugin via openclaw CLI..."
    $out/bin/openclaw plugins install @openclaw/matrix
    
    # Verify the installation
    if [ -d "$out/lib/openclaw/node_modules/@openclaw/matrix" ]; then
      echo "Matrix plugin installed successfully"
      if [ -d "$out/lib/openclaw/node_modules/@vector-im/matrix-bot-sdk" ]; then
        echo "Matrix bot SDK found"
      else
        echo "Warning: Matrix bot SDK not found, checking dependencies..."
        ls -la "$out/lib/openclaw/node_modules/@openclaw/matrix/node_modules/" || true
      fi
    else
      echo "ERROR: Matrix plugin installation failed"
      exit 1
    fi
  '';

  passthru = basePackage.passthru or {};

  meta = basePackage.meta // {
    description = "${basePackage.meta.description or "OpenClaw gateway"} with Matrix plugin";
  };
}

