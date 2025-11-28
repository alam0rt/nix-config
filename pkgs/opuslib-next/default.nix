{ pkgs, lib, python3Packages ? pkgs.python3Packages }:
python3Packages.buildPythonPackage rec {
  pname = "opuslib_next";
  version = "1.1.5";
  format = "wheel";

  src = python3Packages.fetchPypi rec {
    inherit pname version format;
    sha256 = "sha256-n+ylRt/8jadME9V2K0RwqMeo91IOPPf3wAdR5TIj0Ao=";

    dist = "py3";
    python = "py3";
    abi = "none";
    platform = "any";
  };

  meta = with lib; {
    description = "Python bindings to the libopus, IETF low-delay audio codec";
    homepage = "https://pypi.org/project/opuslib_next/";
    license = licenses.bsd3;
    maintainers = with maintainers; [ ];
  };
}
