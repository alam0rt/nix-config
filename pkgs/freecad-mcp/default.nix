{
  lib,
  fetchFromGitHub,
  python3Packages,
  runCommand,
}: let
  pname = "freecad-mcp";
  version = "0.1.17";

  src = fetchFromGitHub {
    owner = "neka-nat";
    repo = "freecad-mcp";
    # v0.1.17 — repo has no tags, pin to the commit the author marked as v0.1.17
    rev = "8694c3214947efedfcf2423b3babad80af80d299";
    hash = "sha256-EYLr7FFIjrPmgngGvYJlQzRPEbYfvp84pIlCbazl/+8=";
  };
in
  python3Packages.buildPythonApplication {
    inherit pname version src;
    pyproject = true;

    build-system = [python3Packages.hatchling];

    dependencies = with python3Packages; [
      mcp
      validators
    ];

    pythonImportsCheck = ["freecad_mcp" "freecad_mcp.server"];

    # The FreeCAD-side addon (InitGui.py, rpc_server/) is a standalone workbench
    # that runs inside FreeCAD's embedded Python. Expose it as a module
    # derivation consumable by `freecad.customize { modules = [ ... ]; }`.
    passthru.addon = runCommand "freecad-mcp-addon-${version}" {} ''
      mkdir -p $out
      cp -r ${src}/addon/FreeCADMCP/. $out/
    '';

    meta = {
      description = "Model Context Protocol server for driving FreeCAD from an LLM";
      homepage = "https://github.com/neka-nat/freecad-mcp";
      license = lib.licenses.mit;
      maintainers = [];
      platforms = lib.platforms.unix;
      mainProgram = "freecad-mcp";
    };
  }
