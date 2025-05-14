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
    sha256 = "0wyy2ksxp95vnh71ybj1bbmqd5ggp13x3mk37pzr99ljs9awy8ka";
  };
  buildInputs = [ zlib ];
}
