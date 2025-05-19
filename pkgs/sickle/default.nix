{
  stdenv,
  fetchFromGitHub,
  zlib,
}:
stdenv.mkDerivation {
  pname = "sickle";
  version = "v1.33";
  src = fetchFromGitHub {
    owner = "najoshi";
    repo = "sickle";
    rev = "v1.33";
    sha256 = "rFVeOZURBOgQ0Q1dK7+IN4KPyQrHB6WdTpj6SwEi2K4=";
  };
  installPhase = ''
    make build
    mkdir -p $out/bin
    cp sickle $out/bin
  '';
  buildInputs = [zlib];
}
