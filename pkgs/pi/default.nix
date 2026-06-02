{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}: let
  pname = "pi";
  version = "0.78.0";

  srcs = {
    x86_64-linux = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
      hash = "sha256-isAzQ9HhIoEG6BchV/Mta4goKeRrNP6vV38XGl8Th8w=";
    };
    aarch64-linux = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256-SRVRc2gkc3INnez03uy+11T66Ekl7wA8C2aqwx1fkAU=";
    };
    x86_64-darwin = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256-ZgdLJxJgBoGZ9Hc4oXI5fx4LWjM0aX3SrOo1u9NHCxw=";
    };
    aarch64-darwin = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256-aOu+T1ahNqHHus4zk+ykrQqh/Z8lO3l/03AFi9Of4HA=";
    };
  };
in
  stdenv.mkDerivation {
    inherit pname version;

    src = srcs.${stdenv.hostPlatform.system} or (throw "Unsupported system: ${stdenv.hostPlatform.system}");

    sourceRoot = "pi";

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      autoPatchelfHook
    ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      stdenv.cc.cc.lib
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/lib/pi
      cp -r . $out/lib/pi/
      ln -s $out/lib/pi/pi $out/bin/pi

      runHook postInstall
    '';

    dontStrip = true;

    meta = {
      description = "Terminal-based AI coding agent supporting 15+ LLM providers";
      homepage = "https://pi.dev";
      license = lib.licenses.mit;
      maintainers = [];
      platforms = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
      mainProgram = "pi";
    };
  }
