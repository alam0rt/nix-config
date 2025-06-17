{
  stdenv,
  fetchFromGitHub,
  buildPythonPackage,
  lib,
}:
  buildPythonPackage rec {
    pname = "propagandabot";
    version = "v0.0.0-1";
    src = fetchFromGitHub {
      owner = "ult1m4";
      repo = "PropagandaBot";
      rev = "4255d5c6e8d9822bcb37b27af45e5e4ee9639494";
      sha256 = "ijjKHbk5bgPuAgYRNwoTaoR9HWXZREXBLpfVzbwnmOs=";
    };
    vendorHash = "sha256-QcGAnfjcka5JxLm/3NAeswAPohCNEUrWCLvajs2lLyw=";
    
    meta = {
      description = "Fork of Botamusique to support YT-DLP and modern stream functionality. Intended to be static, with manual updates to YT-DLP.";
      license = lib.licenses.mit;
      homepage = "https://github.com/${src.owner}/${src.repo}";
    };
  }
