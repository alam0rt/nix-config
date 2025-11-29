{
  pkgs,
  lib,
  python3Packages ? pkgs.python3Packages,
}:
python3Packages.buildPythonPackage rec {
  pname = "protobuf";
  version = "3.20.3";
  src = python3Packages.fetchPypi {
    inherit pname version;
    sha256 = "sha256-LjQnQpyc/+vyWUkb4K9wGJYH82XC9Bx8N2SvbzNxBfI=";
  };

  meta = with lib; {
    description = "Python bindings for Opus codec (next generation)";
    homepage = "https://pypi.org/project/opuslib_next/";
    license = licenses.bsd3;
    maintainers = with maintainers; [];
  };
}
