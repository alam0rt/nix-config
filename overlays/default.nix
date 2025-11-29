# This file defines overlays
{inputs, ...}: {

  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final.pkgs;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: let
    pythonEnv = prev.python3.withPackages (ps: [
      final.opuslib-next # local
      final.protobuf3 # local
      ps.flask
      ps.mutagen
      ps.packaging
      ps.pillow
      ps.pycryptodome
      ps.pyradios
      ps.python-magic
      ps.requests
      ps.yt-dlp
    ]);
  in {
        botamusique = prev.botamusique.overrideAttrs (old: rec {
          src = prev.fetchFromGitHub {
            repo = "botamusique";
            owner = "algielen";
            rev = "190b8e3659ecbae787b0b90a3c3bbf1a4fca494a";
            sha256 = "sha256-aDWTk1w9lknB5Vu3azrXzRhA7Q4LsN/xMo3VDL2alLM=";
          };

          patches = [];

          # Remove npm dependencies
          npmDeps = null;
          npmRoot = null;

          # Remove NODE_OPTIONS since we're not using Node
          NODE_OPTIONS = null;

          # Update Python dependencies to match pyproject.toml
          pythonPath = with prev.python3Packages; [
            final.opuslib-next # local
            final.protobuf3 # local
            flask
            mutagen
            packaging
            pillow
            pycryptodome
            pyradios
            python-magic
            requests
            yt-dlp
          ] ++ prev.lib.optionals prev.stdenv.isLinux [
            # audioop-lts is needed for Python 3.13+ (audioop was removed)
            # This may need to be packaged separately for Nix if not available
          ];

          installPhase = ''
            runHook preInstall

            mkdir -p $out/share $out/bin
            cp -r . $out/share/botamusique

            # Create wrapper for the main script with proper Python environment
            makeWrapper ${pythonEnv}/bin/python3 $out/bin/botamusique \
              --add-flags "$out/share/botamusique/mumbleBot.py" \
              --prefix PYTHONPATH : "$out/share/botamusique" \
              --prefix PATH : ${prev.lib.makeBinPath [ final.ffmpeg-headless ]}

            runHook postInstall
          '';

          #makeWrapperArgs = (old.makeWrapperArgs or []) ++ [
          #  "--set PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION python"
          #  "--prefix LD_LIBRARY_PATH : ${prev.libopus}/lib"
          #];
          # Replace Node.js with Deno in build inputs
          nativeBuildInputs = builtins.map 
            (pkg: if pkg == prev.nodejs then prev. deno else pkg)
            (builtins.filter 
              (pkg: pkg != prev.npmHooks.npmConfigHook)
              old.nativeBuildInputs);

          # Override the build phase to skip the web frontend build
          buildPhase = ''
            runHook preBuild
            runHook postBuild
          '';

          # Update meta to note the limitation
          meta = old.meta // {
            description = old.meta.description + " (built without web frontend)";
          };
        });
    # example = prev.example.overrideAttrs (oldAttrs: rec {
    # ...
  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.system;
      config.allowUnfree = true;
    };
  };
}
