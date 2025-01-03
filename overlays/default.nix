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
    # example = prev.example.overrideAttrs (oldAttrs: rec {
    # ...
    # });
    #  shadps4 = prev.shadps4.overrideAttrs (oldAttrs: {
    #    pname = "shadps4";
    #    version = "0.5.0-unstable-2024-12-26";
    #    src = prev.fetchFromGitHub {
    #      owner = "shadps4-emu";
    #      repo = "shadPS4";
    #      rev = "a1a98966eee07e7ecf3a5e3836b5f2ecde5664b0";
    #      hash = "";
    #      fetchSubmodules = true;
    #    };
    #  });
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
