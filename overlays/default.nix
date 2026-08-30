# This file defines overlays
{inputs, ...}: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final.pkgs;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev:
    {
      # gpac 26.07 turned strcpy/strcat/strncpy into `#define strcpy #error "..."`
      # in gpac/setup.h unless GPAC_ALLOW_UNSAFE_STRFUNC is defined first.
      # ccextractor includes those headers and still calls strcpy, so it fails to
      # compile with "stray '#' in program" in mp4.c and params.c.
      #
      # setup.h documents this define as the supported opt-out. It only restores
      # the behaviour ccextractor already had before gpac added the poison — the
      # safety of its own strcpy call sites is unchanged either way.
      #
      # Pulled in here by tdarr, which puts ccextractor on the node's PATH and
      # sets the server's ccextractorPath. Drop this once nixpkgs' ccextractor
      # builds against gpac >= 26.07 on its own.
      ccextractor = prev.ccextractor.overrideAttrs (old: {
        env =
          (old.env or {})
          // {
            NIX_CFLAGS_COMPILE = builtins.concatStringsSep " " [
              (old.env.NIX_CFLAGS_COMPILE or "")
              "-DGPAC_ALLOW_UNSAFE_STRFUNC"
            ];
          };
      });
    }
    // (import ./botamusique final prev);

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
      config.cudaSupport = true;
    };
  };
}
