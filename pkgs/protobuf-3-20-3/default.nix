{ pkgs, lib, python3Packages ? pkgs.python3Packages }:
python3Packages.buildPythonPackage rec {
  pname = "opuslib_next";
  version = "1.1.5";
  src = python3Packages.fetchPypi {
    inherit pname version;
  };

  meta = with lib; {
    description = "Python bindings for Opus codec (next generation)";
    homepage = "https://pypi.org/project/opuslib_next/";
    license = licenses.bsd3;
    maintainers = with maintainers; [ ];
  };
}
