# This file defines overlays
{inputs, ...}: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final.pkgs;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
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
            pkgs.opuslib-next # local
            flask
            mutagen
            packaging
            pillow
            protobuf  # Fixed at 3.20.3 in pyproject.toml
            pycryptodome
            pyradios
            python-magic
            requests
            yt-dlp
          ] ++ prev.lib.optionals prev.stdenv.isLinux [
            # audioop-lts is needed for Python 3.13+ (audioop was removed)
            # This may need to be packaged separately for Nix if not available
          ];

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

	  postInstall = (old.postInstall or "") + ''
	    wrapProgram $out/bin/botamusique --set PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION python --prefix LD_LIBRARY_PATH : ${prev.libopus}/lib
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
