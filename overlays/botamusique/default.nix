final: prev: let
  pythonEnv = prev.python3.withPackages (ps: [
    final.opuslib-next # local
    ps.audioop-lts
    ps.flask
    ps.mutagen
    ps.packaging
    ps.pillow
    ps.protobuf
    ps.pycryptodome
    ps.pyradios
    ps.python-magic
    ps.requests
    ps.yt-dlp
  ]);
in {
  botamusique = prev.botamusique.overrideAttrs (old: {
    version = "v8.3.4";
    
    src = prev.fetchFromGitHub {
      repo = "botamusique";
      owner = "algielen";
      rev = "8332323ff83df5df316aa1792f284fa5d72c482b";
      sha256 = "sha256-LTkosBgubV2fYjrNbEETm3LVD1putVCNrBfC59RWp+8=";
    };

    patches = [
      ./circular-import.patch
    ];

    # Remove npm dependencies
    npmDeps = null;
    npmRoot = null;

    # Remove NODE_OPTIONS since we're not using Node
    NODE_OPTIONS = null;

    # Update Python dependencies to match pyproject.toml
    pythonPath = with prev.python3Packages;
      [
        final.opuslib-next # local
        audioop-lts
        flask
        mutagen
        packaging
        pillow
        protobuf
        pycryptodome
        pyradios
        python-magic
        requests
        yt-dlp
      ]
      ++ prev.lib.optionals prev.stdenv.isLinux [
        # Additional Linux-specific dependencies if needed
      ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share $out/bin
      cp -r . $out/share/botamusique

      # Create wrapper for the main script with proper Python environment
      makeWrapper ${pythonEnv}/bin/python3 $out/bin/botamusique \
        --add-flags "$out/share/botamusique/main.py" \
        --prefix PYTHONPATH : "$out/share/botamusique" \
        --prefix PATH : ${prev.lib.makeBinPath [final.ffmpeg-headless]}

      runHook postInstall
    '';

    # Replace Node.js with Deno in build inputs
    nativeBuildInputs =
      builtins.map
      (pkg:
        if pkg == prev.nodejs
        then prev. deno
        else pkg)
      (builtins.filter
        (pkg: pkg != prev.npmHooks.npmConfigHook)
        old.nativeBuildInputs);

    # Override the build phase to skip the web frontend build
    buildPhase = ''
      runHook preBuild
      runHook postBuild
    '';

    # Update meta to note the limitation
    meta =
      old.meta
      // {
        description = old.meta.description + " (built without web frontend)";
      };
  });
}
