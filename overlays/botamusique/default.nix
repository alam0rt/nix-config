final: prev: let
  # The fork needs Python >= 3.14 and newer deps than stable nixpkgs carries,
  # so build the whole thing against nixpkgs-unstable.
  python3Packages = final.unstable.python3Packages;

  # YouTube breaks yt-dlp constantly; track the latest release rather than
  # whatever nixpkgs has. nixpkgs' yt-dlp hardcodes deno as its JS runtime,
  # which YouTube now needs, and bundles the matching yt-dlp-ejs.
  # Keep yt-dlp-ejs in sync with yt-dlp's pyproject.toml when bumping.
  yt-dlp = python3Packages.toPythonModule (final.unstable.yt-dlp.overridePythonAttrs (old: rec {
    version = "2026.10.26";
    src = prev.fetchFromGitHub {
      owner = "yt-dlp";
      repo = "yt-dlp";
      tag = version;
      hash = "sha256-0gX99Q45+1L4eH0YK0942DVTq5Wwscq3Qkj+N/EjHek=";
    };
  }));
in {
  botamusique = python3Packages.buildPythonApplication {
    pname = "botamusique";
    version = "8.9.7-unstable-2026-10-29";
    pyproject = true;

    src = prev.fetchFromGitHub {
      owner = "algielen";
      repo = "botamusique";
      rev = "d9374cae5a39c3abed5cfd193df04d9ce226ccec";
      hash = "sha256-P3k0o3fuzCNsV980XTYUqZS6KKGkqyqC3xnI7zd4jdQ=";
    };

    # The hatch build hook runs scripts/build.py, which downloads Bootswatch
    # CSS from a CDN and re-renders the translated templates. Both outputs are
    # committed, and the hook skips itself when the script is missing.
    postPatch = ''
      rm scripts/build.py
    '';

    build-system = with python3Packages; [
      hatchling
      jinja2
    ];

    dependencies = with python3Packages; [
      audioop-lts
      certifi
      filetype
      flask
      mutagen
      opuslib-next
      pillow
      protobuf
      pycryptodome
      pyradios
      requests
      werkzeug
      yt-dlp
    ];

    # Lower bounds come from upstream's dependabot bumps and run ahead of
    # nixpkgs-unstable. certifi is patched in nixpkgs to use the system CA
    # bundle, so its version doesn't govern trust anyway.
    pythonRelaxDeps = [
      "certifi"
      "pycryptodome"
      "werkzeug"
    ];

    makeWrapperArgs = [
      "--prefix"
      "PATH"
      ":"
      (prev.lib.makeBinPath [final.ffmpeg-headless])
    ];

    pythonImportsCheck = [
      "botamusique"
      "pymumble_py3"
    ];

    meta = {
      description = "Bot to play youtube / soundcloud / radio / local music on Mumble";
      homepage = "https://github.com/algielen/botamusique";
      license = prev.lib.licenses.mit;
      mainProgram = "botamusique";
    };
  };
}
