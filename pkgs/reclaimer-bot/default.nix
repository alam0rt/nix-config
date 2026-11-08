{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:
# Project Reclaimer's bot for a dedicated server's chat and voice (a DJ, an
# announcer, a relay to another chat). No game, display or sound device;
# links only glibc and libgcc_s. BOT.md (in share/doc) is the guide.
stdenv.mkDerivation (finalAttrs: {
  pname = "reclaimer-bot";
  version = "0.10.1";

  src = fetchurl {
    url = "https://github.com/ProjectReclaimer/project-reclaimer-releases/releases/download/v${finalAttrs.version}/reclaimer-bot-v${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha256-wRyYRuBYM32SGgA7u4JK9+hiFauKrh3QhZ9rQz3a0rQ=";
  };

  nativeBuildInputs = [autoPatchelfHook];
  buildInputs = [stdenv.cc.cc.lib];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 reclaimer-bot $out/bin/reclaimer-bot
    install -Dm644 -t $out/share/doc/reclaimer-bot BOT.md README.txt THIRD-PARTY-LICENSES.txt LICENSE-fsbex.txt
    runHook postInstall
  '';

  meta = {
    description = "Chat and voice bot for Project Reclaimer dedicated servers";
    homepage = "https://projectreclaimer.dev/host#bots";
    license = lib.licenses.unfree;
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    platforms = ["x86_64-linux"];
    mainProgram = "reclaimer-bot";
    maintainers = [];
  };
})
