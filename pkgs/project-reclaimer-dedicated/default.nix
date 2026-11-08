{
  lib,
  stdenvNoCC,
  fetchurl,
}:
# Project Reclaimer's server-only package for Linux: one program,
# `project-reclaimer`, that runs `dedicated` servers natively (no Wine, no
# display). It needs only glibc >= 2.36 and libgcc_s.
#
# Not patched or wrapped on purpose: this is the seed services.reclaimer
# copies into a writable folder, where upstream's `auto_update` replaces it
# with each new release (several a week). That copy runs through nix-ld. Bump
# the version here now and then so a fresh install starts close to current.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "project-reclaimer-dedicated";
  version = "0.10.1";

  src = fetchurl {
    url = "https://github.com/ProjectReclaimer/project-reclaimer-releases/releases/download/v${finalAttrs.version}/project-reclaimer-dedicated-v${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha256-GXMR6qBiZsM0B0QrxgD55aOBC4woqnfRDapjeRl14nM=";
  };

  dontConfigure = true;
  dontBuild = true;
  # Kept byte for byte as released: the updater replaces these files in the
  # writable copy, and the program checks nothing against the store.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/project-reclaimer
    cp -r . $out/share/project-reclaimer/
    runHook postInstall
  '';

  meta = {
    description = "Project Reclaimer dedicated server (Halo 3 on MCC's files), unpatched seed copy";
    homepage = "https://projectreclaimer.dev/host";
    license = lib.licenses.unfree;
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    platforms = ["x86_64-linux"];
    maintainers = [];
  };
})
