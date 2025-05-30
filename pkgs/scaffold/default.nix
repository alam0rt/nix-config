{
  stdenv,
  fetchFromGitHub,
  buildGoModule,
  lib,
}:
  buildGoModule rec {
    pname = "scaffold";
    version = "v0.7.0";
    src = fetchFromGitHub {
      owner = "hay-kot";
      repo = pname;
      rev = version;
      sha256 = "WkllVAPIlWpKFKppsFyEO8x1c0kSD6kw1lsm/h3opu0=";
    };
    vendorHash = "sha256-vZK5bjbvJ2mu4k3uKoTm1nWIKt0L9bAXq6geoHVRt+A=";
    
    meta = {
      description = "A cookie cutter alternative with in-project scaffolding for generating components, controllers, or other common code patterns";
      license = lib.licenses.mit;
      homepage = "https://github.com/${src.owner}/${src.repo}";
    };
  }
