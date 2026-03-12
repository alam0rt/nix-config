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
    export PATH="${nodejs_22}/bin:${pnpm_10}/bin:$PATH"
    export OPENCLAW_STATE_DIR="$out/lib/openclaw"
    export NODE_PATH="$out/lib/openclaw/node_modules"
    
    # Create a temporary package.json in the openclaw directory for pnpm to use
    cd "$out/lib/openclaw"
    
    # Install the Matrix plugin using pnpm directly
    # This will install @openclaw/matrix and its dependencies including @vector-im/matrix-bot-sdk
    echo "Installing Matrix plugin with pnpm..."
    ${pnpm_10}/bin/pnpm add @openclaw/matrix@latest --save-prod --no-lockfile || {
      echo "Failed to install Matrix plugin, trying with npm..."
      ${nodejs_22}/bin/npm install --no-save --no-package-lock @openclaw/matrix || {
        echo "Warning: Matrix plugin installation failed"
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

