{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  python3,
}: let
  version = "5.10.0";

  # v5.10.0 is the last release pinned to Ghidra 12.0.4 (what nixpkgs ships).
  # v5.11.0+ require Ghidra 12.1.
  extensionZip = fetchurl {
    url = "https://github.com/bethington/ghidra-mcp/releases/download/v${version}/GhidraMCP-${version}.zip";
    hash = "sha256-9zstlnq9t0B6hoRhOZADAcOnVhbfxLtB7geEG0pVo88=";
  };

  bridgeScript = fetchurl {
    url = "https://github.com/bethington/ghidra-mcp/releases/download/v${version}/bridge_mcp_ghidra.py";
    hash = "sha256-cWbElgLBTYHNaExU2OphkuYQTCeuH8GgYMP5CDvqSxw=";
  };

  pythonEnv = python3.withPackages (p: [p.mcp p.requests]);

  extension = stdenvNoCC.mkDerivation {
    pname = "ghidra-mcp";
    inherit version;

    src = extensionZip;
    dontUnpack = true;

    nativeBuildInputs = [unzip];

    # Matches the layout produced by ghidra.buildGhidraExtension so that
    # ghidra.withExtensions picks it up identically to a built-from-source ext.
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/ghidra/Ghidra/Extensions
      unzip -d $out/lib/ghidra/Ghidra/Extensions $src
      touch $out/lib/ghidra/Ghidra/Extensions/GhidraMCP/.dbDirLock
      runHook postInstall
    '';

    passthru.bridge = bridge;

    meta = {
      description = "Ghidra MCP Server — 200+ MCP tools for AI-driven reverse engineering";
      homepage = "https://github.com/bethington/ghidra-mcp";
      downloadPage = "https://github.com/bethington/ghidra-mcp/releases/tag/v${version}";
      license = lib.licenses.mit;
      maintainers = [];
      platforms = lib.platforms.unix;
    };
  };

  bridge = stdenvNoCC.mkDerivation {
    pname = "ghidra-mcp-bridge";
    inherit version;

    src = bridgeScript;
    dontUnpack = true;

    # Upstream ships the bridge as a PEP 723 inline-script (no shebang);
    # prepend an interpreter that has mcp + requests available.
    installPhase = ''
      runHook preInstall
      install -d $out/bin
      {
        echo '#!${pythonEnv}/bin/python3'
        cat $src
      } > $out/bin/ghidra-mcp-bridge
      chmod +x $out/bin/ghidra-mcp-bridge
      runHook postInstall
    '';

    meta =
      extension.meta
      // {
        mainProgram = "ghidra-mcp-bridge";
        description = "MCP↔HTTP bridge that fronts the GhidraMCP plugin";
      };
  };
in
  extension
