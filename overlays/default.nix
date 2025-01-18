# This file defines overlays
{inputs, ...}: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final.pkgs;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    # example = prev.example.overrideAttrs (oldAttrs: rec {
    # ...
    # });
    botamusique = prev.botamusique.overrideAttrs (oldAttrs: rec {
      version = "7.2.3";
      src = prev.fetchFromGitHub {
        owner = "azlux";  # Replace with the actual owner
        repo = "botamusique";
        rev = "2760a14f01004216ec1411c33f953b10c51bca09";  # Replace with the commit SHA of the new version
        sha256 = "";  # Replace with the actual SHA256 hash
      };
    });
  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.system;
      config.allowUnfree = true;
    };
  };
}
