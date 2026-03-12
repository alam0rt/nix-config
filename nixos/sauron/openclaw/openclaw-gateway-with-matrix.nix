{ lib
, stdenv
, makeWrapper
, nodejs_22
, pnpm_10
, basePackage
}:

stdenv.mkDerivation {
  pname = "${basePackage.pname}-with-matrix";
  version = basePackage.version;

  dontUnpack = true;
  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper nodejs_22 pnpm_10 ];

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
    $out/bin/openclaw plugins install @openclaw/matrix || {
      echo "Warning: Matrix plugin installation failed"
      echo "Trying manual npm install as fallback..."
      cd "$out/lib/openclaw"
      ${nodejs_22}/bin/npm install --no-save --no-package-lock @openclaw/matrix || {
        echo "Warning: Manual installation also failed"
        echo "Service will start but Matrix channel will not be available"
      }
    }
    
    # Verify the installation
    if [ -d "$out/lib/openclaw/node_modules/@openclaw/matrix" ]; then
      echo "Matrix plugin installed successfully"
      if [ -d "$out/lib/openclaw/node_modules/@vector-im/matrix-bot-sdk" ]; then
        echo "Matrix bot SDK found"
      else
        echo "Warning: Matrix bot SDK not found, Matrix plugin may not work"
      fi
    fi
  '';

  passthru = basePackage.passthru or {};

  meta = basePackage.meta // {
    description = "${basePackage.meta.description or "OpenClaw gateway"} with Matrix plugin";
  };
}

