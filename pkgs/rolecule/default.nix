{
  stdenv,
  fetchFromGitHub,
  buildGoModule,
  lib,
}:
  buildGoModule rec {
    pname = "rolecule";
    version = "v0.6.1";
    src = fetchFromGitHub {
      owner = "z0mbix";
      repo = pname;
      rev = version;
      sha256 = "WkllVAPIlWpKFKppsFyEO8x1c0kSD6kw1lsm/h3opu0=";
    };
    vendorHash = "sha256-vZK5bjbvJ2mu4k3uKoTm1nWIKt0L9bAXq6geoHVRt+A=";
    
    meta = {
      description = "Small, simple tool to test your ansible roles";
      license = lib.licenses.gpl3;
      homepage = "https://github.com/z0mbix/rolecule";
    };
  }
