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
        rev = "a1e9994f5cc325a647a9df9984eec623a4b57b01";
        sha256 = "sha256-CSXmAMSVdv2G1VquHmL/28gfTWoQOpuWvaOqOmJgonk=";
      };
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
