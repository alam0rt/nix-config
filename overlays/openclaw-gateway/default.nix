final: prev: let
  # Build the Matrix plugin for OpenClaw
  # The plugin contains @vector-im/matrix-bot-sdk as a dependency
  openclaw-matrix-plugin = final.buildNpmPackage rec {
    pname = "openclaw-matrix";
    version = "0.0.1";

    src = final.fetchFromGitHub {
      owner = "openclaw";
      repo = "openclaw";
      # Use the same rev as the openclaw-gateway package
      rev = prev.openclaw-gateway.passthru.pinnedRev or "7c889e71136adc0250fe25e283d219563f50a5e8";
      hash = "sha256-2oTtcUyhLxsByvZhCnxSlN63zhlyQJ7DMjyAva2McN0=";
    };

    sourceRoot = "source/extensions/matrix";

    npmDepsHash = "sha256-0000000000000000000000000000000000000000000="; # Will be updated after first build

    # Don't run build scripts, just install dependencies
    dontNpmBuild = true;

    installPhase = ''
      runHook preInstall
      
      # Create the output structure for the plugin
      mkdir -p $out/lib/node_modules/@openclaw/matrix
      
      # Copy the plugin files
      cp -r . $out/lib/node_modules/@openclaw/matrix/
      
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "Matrix channel plugin for OpenClaw";
      homepage = "https://github.com/openclaw/openclaw";
      license = licenses.mit;
    };
  };
in {
  openclaw-gateway = prev.openclaw-gateway.overrideAttrs (oldAttrs: {
    postInstall = (oldAttrs.postInstall or "") + ''
      # Add the Matrix plugin to make it available to openclaw-gateway
      # This is needed because the Matrix plugin is not bundled with the core install
      # and normally would be installed via: openclaw plugins install @openclaw/matrix
      
      echo "Installing Matrix plugin for OpenClaw..."
      
      # Symlink the matrix plugin into node_modules
      mkdir -p "$out/lib/openclaw/node_modules/@openclaw"
      if [ ! -e "$out/lib/openclaw/node_modules/@openclaw/matrix" ]; then
        ln -s "${openclaw-matrix-plugin}/lib/node_modules/@openclaw/matrix" \
              "$out/lib/openclaw/node_modules/@openclaw/matrix"
        echo "Matrix plugin installed at node_modules/@openclaw/matrix"
      fi
    '';
  });
}
