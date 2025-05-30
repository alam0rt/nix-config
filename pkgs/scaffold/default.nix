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
      sha256 = "ijjKHbk5bgPuAgYRNwoTaoR9HWXZREXBLpfVzbwnmOs=";
    };
    vendorHash = "sha256-QcGAnfjcka5JxLm/3NAeswAPohCNEUrWCLvajs2lLyw=";
    
    meta = {
      description = "A cookie cutter alternative with in-project scaffolding for generating components, controllers, or other common code patterns";
      license = lib.licenses.mit;
      homepage = "https://github.com/${src.owner}/${src.repo}";
    };
  }
