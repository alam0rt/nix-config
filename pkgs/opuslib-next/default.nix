{ pkgs, lib, setuptools, fetchpatch, python3Packages ? pkgs.python3Packages }:
python3Packages.buildPythonPackage rec {
  pname = "opuslib_next";
  version = "1.1.5";

  src = python3Packages.fetchPypi rec {
    inherit pname version;
    sha256 = "sha256-auwQFfJfeZeU0hdgHHTqD66P1l11JXjLFj/SM47Qdc4=";
  };

  patches = [
    # https://github.com/orion-labs/opuslib/pull/22
    (fetchpatch {
      name = "opuslib-paths.patch";
      url = "https://github.com/NixOS/nixpkgs/blob/9a7b80b6f82a71ea04270d7ba11b48855681c4b0/pkgs/development/python-modules/opuslib/opuslib-paths.patch";
      hash = "sha256-oa1HCFHNS3ejzSf0jxv9NueUKOZgdCtpv+xTrjYW5os=";
    })
  ];

  dependencies = [pkgs.libopus];

  build-system = [ setuptools ];

  meta = with lib; {
    description = "Python bindings to the libopus, IETF low-delay audio codec";
    homepage = "https://pypi.org/project/opuslib_next/";
    license = licenses.bsd3;
    maintainers = with maintainers; [ ];
  };
}
