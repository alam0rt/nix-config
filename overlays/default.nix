# This file defines overlays
{inputs, ...}: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final.pkgs;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    botamusique = prev.botamusique.overrideAttrs (old: rec {
      src = prev.fetchFromGitHub {
        repo = "botamusique";
        owner = "alam0rt";
        rev = "aa0b8f65847d0ac37e2bf5e11f07213751ebfdb0";
        sha256 = "sha256-CSXmAMSVdv2G1VquHmL/28gfTWoQOpuWvaOqOmJgonk=";
        version = "7.2.3";
      };
      patches = [];
    });
    # example = prev.example.overrideAttrs (oldAttrs: rec {
    # ...
    # });
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
