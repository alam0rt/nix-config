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
            owner = "algielen";
            rev = "190b8e3659ecbae787b0b90a3c3bbf1a4fca494a";
            sha256 = "sha256-CSXmAMSVdv2G1VquHmL/28gfTWoQOpuWvaOqOmJgonk=";
          };
    #      npmDeps = prev.fetchNpmDeps {
    #        src = "${src}/web";
    #        hash = "sha256-Pq+2L28Zj5/5RzbgQ0AyzlnZIuRZz2/XBYuSU+LGh3I=";
    #      };
    #      patches = [];
    #      version = "7.2.3";
    #    });
    # example = prev.example.overrideAttrs (oldAttrs: rec {
    # ...
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
