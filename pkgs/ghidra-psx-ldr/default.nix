{
  lib,
  fetchFromGitHub,
  ghidra,
}:
ghidra.buildGhidraExtension (finalAttrs: {
  pname = "ghidra-psx-ldr";
  version = "2025.09.06";

  src = fetchFromGitHub {
    owner = "lab313ru";
    repo = "ghidra_psx_ldr";
    rev = finalAttrs.version;
    hash = "sha256-xUb3Zo4LcbkOgkH1OaConUC4vqfo5KgpdC2VtDrMe5E=";
    fetchSubmodules = true;
  };

  # Compile the SLEIGH file before building the extension
  preBuild = ''
    # Remove the pre-compiled .sla file (it's in an old XML format)
    rm -f data/languages/mips32le.sla
    # Compile the .slaspec file using Ghidra's sleigh compiler
    ${ghidra}/lib/ghidra/support/sleigh data/languages/mips32le.slaspec data/languages/mips32le.sla
  '';

  meta = {
    description = "Sony PlayStation PSX executables loader for Ghidra";
    homepage = "https://github.com/lab313ru/ghidra_psx_ldr";
    downloadPage = "https://github.com/lab313ru/ghidra_psx_ldr/releases/tag/${finalAttrs.version}";
    license = lib.licenses.asl20;
    maintainers = [];
    platforms = lib.platforms.unix;
  };
})
