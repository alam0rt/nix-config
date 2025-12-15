# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  outputs,
  lib,
  config,
  ...
}: {
  # You can import other NixOS modules here
  imports = [
    ./config/common
    ./config/secrets
  ];

  # https://github.com/nix-community/nix-ld
  programs.nix-ld.enable = true;

  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      inputs.llama-cpp.overlays.default
      # # Patch ROCm variant inside llamaPackages
      # (final: prev: {
      #   llamaPackages = prev.llamaPackages // {
      #     llama-cpp = prev.llamaPackages.llama-cpp.overrideAttrs (old: {
      #       nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ final.lld final.llvm ];
      #       preConfigure = (old.preConfigure or "") + ''
      #         export PATH=${final.lld}/bin:${final.llvm}/bin:$PATH
      #         export HIP_LD=${final.lld}/bin/ld.lld
      #       '';
      #     });
      #   };
      # })
    ];
    config = {
      allowUnfree = true;
    };
  };

  nix = let
    flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  in {
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Opinionated: disable global registry
      flake-registry = "";
      # Workaround for https://github.com/NixOS/nix/issues/9574
      nix-path = config.nix.nixPath;
    };
    # Opinionated: disable channels
    channel.enable = false;

    # Opinionated: make flake registry and nix path match flake inputs
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };

  # Use the systemd-boot EFI boot loader.
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
    };
  };

  # Set your time zone.
  time.timeZone = "Australia/Melbourne";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # allow interacting with secret store
  environment.systemPackages = [inputs.agenix.packages.x86_64-linux.default];

  environment.localBinInPath = true;

  programs.zsh.enable = true;

  # Prevent the new user dialog in zsh
  system.userActivationScripts.zshrc = "touch .zshrc";

  # This setups a SSH server. Very important if you're setting up a headless system.
  # Feel free to remove if you don't need it.
  services.openssh = {
    enable = true;
    settings = {
      # Opinionated: forbid root login through SSH.
      PermitRootLogin = "no";
      # Opinionated: use keys only.
      # Remove if you want to SSH using passwords
      PasswordAuthentication = false;
      X11Forwarding = true;
    };
  };
}
