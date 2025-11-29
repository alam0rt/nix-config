{ pkgs, lib, libopus, replaceVars, stdenv, python3Packages ? pkgs.python3Packages }:
python3Packages.buildPythonPackage rec {
  pname = "opuslib_next";
  version = "1.1.5";

  src = python3Packages.fetchPypi rec {
    inherit pname version;
    sha256 = "sha256-auwQFfJfeZeU0hdgHHTqD66P1l11JXjLFj/SM47Qdc4=";
  };

  patches = [
    (replaceVars ./opuslib-paths.patch {
      opusLibPath = "${libopus}/lib/libopus${stdenv.hostPlatform.extensions.sharedLibrary}";
    })
  ];
  dependencies = [pkgs.libopus];

  build-system = [ python3Packages.setuptools ];

  meta = with lib; {
    description = "Python bindings to the libopus, IETF low-delay audio codec";
    homepage = "https://pypi.org/project/opuslib_next/";
    license = licenses.bsd3;
    maintainers = with maintainers; [ ];
  };
}
