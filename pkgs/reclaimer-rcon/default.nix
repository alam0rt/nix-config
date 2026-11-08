{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  libGL,
  libglvnd,
  libx11,
  libxcursor,
  libxi,
  libxrender,
  libxkbcommon,
  wayland,
}:
# Project Reclaimer's remote console window, for a dedicated server's RCON
# (Source RCON and WebSocket on its game port). A desktop app: it links only
# glibc and libgcc_s and dlopens X11 or Wayland and GL at run time, which the
# wrapper puts on its library path. On the server itself,
# `reclaimer rcon` (services.reclaimer's wrapper) is the command-line one.
stdenv.mkDerivation (finalAttrs: {
  pname = "reclaimer-rcon";
  version = "0.10.1";

  src = fetchurl {
    url = "https://github.com/ProjectReclaimer/project-reclaimer-releases/releases/download/v${finalAttrs.version}/reclaimer-rcon-v${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha256-BdgLsKS1qNTAt1YQxB6pWeuMoJoWRF4j5m4zcmBMmCQ=";
  };

  nativeBuildInputs = [autoPatchelfHook makeWrapper];
  buildInputs = [stdenv.cc.cc.lib];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 reclaimer-rcon $out/libexec/reclaimer-rcon
    makeWrapper $out/libexec/reclaimer-rcon $out/bin/reclaimer-rcon \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [libGL libglvnd libx11 libxcursor libxi libxrender libxkbcommon wayland]}
    install -Dm644 project-reclaimer.png $out/share/icons/hicolor/256x256/apps/project-reclaimer.png
    install -Dm644 project-reclaimer-rcon.desktop $out/share/applications/project-reclaimer-rcon.desktop
    substituteInPlace $out/share/applications/project-reclaimer-rcon.desktop \
      --replace-quiet "@INSTALL@/reclaimer-rcon" "$out/bin/reclaimer-rcon" \
      --replace-quiet "@INSTALL@" "$out/libexec"
    install -Dm644 -t $out/share/doc/reclaimer-rcon RCON.md README.txt THIRD-PARTY-LICENSES.txt LICENSE-fsbex.txt
    runHook postInstall
  '';

  meta = {
    description = "Remote console for Project Reclaimer dedicated servers";
    homepage = "https://projectreclaimer.dev/host#remote-console-rcon";
    license = lib.licenses.unfree;
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    platforms = ["x86_64-linux"];
    mainProgram = "reclaimer-rcon";
    maintainers = [];
  };
})
