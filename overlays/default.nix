# This file defines overlays
{inputs, ...}: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final.pkgs;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: let
    # Tdarr ships a pkg-bundled `runtime/pnpm`, which the server and node invoke
    # at job time to install plugin dependencies (e.g. `pnpm add import-fresh`).
    # nixpkgs runs autoPatchelfHook over the whole tree; patchelf rewrites that
    # ELF and pkg then reads its embedded payload from the wrong offset, so pnpm
    # dies with `pkg/prelude/bootstrap.js:1 / alloc / SyntaxError: Invalid or
    # unexpected token`. The node cannot install the dependency, so every job
    # fails the instant it starts, with "Transcode error" and lastPluginDetails
    # "none" — no ffmpeg is ever run, which makes it look like a GPU problem.
    #
    # Bisected against the pristine binary from the upstream zip: `strip` alone
    # leaves pnpm working (10.24.0), `patchelf` alone reproduces the SyntaxError.
    # So restore the untouched binary after fixup. It keeps its /lib64
    # interpreter, which nix-ld resolves — verified with an empty environment,
    # as the systemd units run it.
    #
    # Drop this once nixpkgs excludes runtime/ from autoPatchelf upstream.
    keepPristinePnpm = pkg:
      pkg.overrideAttrs (old: {
        # The postFixup attribute runs before autoPatchelfHook's own postFixup
        # hook, so restoring the binary there just gets it re-patched (and in
        # fact fails, since the restored copy is read-only). Drive autoPatchelf
        # by hand instead, then put the pristine pnpm back afterwards.
        dontAutoPatchelf = true;
        postFixup =
          (old.postFixup or "")
          + ''
            autoPatchelf -- $out
            install -Dm555 ${old.src}/runtime/pnpm $out/share/${old.pname}/runtime/pnpm
          '';
      });
  in
    {
      # pkgs.tdarr is a symlinkJoin of these two, and the NixOS module's units
      # run tdarr.passthru.{server,node}, so overriding the leaves is what
      # actually reaches the services.
      tdarr-server = keepPristinePnpm prev.tdarr-server;
      tdarr-node = keepPristinePnpm prev.tdarr-node;

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
