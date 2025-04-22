# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../config/common
      ../config/zfs.nix
      ../config/network
      ../config/nvidia.nix
      ./maubot.nix
      ./mumble.nix
      ./borg.nix
      ./vaultwarden.nix
      ./transmission.nix
      ./nas.nix
      ./unifi.nix
      ./mail.nix
      ./pvpgn.nix
      ./media.nix
      ./nginx.nix
      ./syncthing.nix
      ./openwebui.nix
      ./matrix.nix
      ./monitoring.nix
      ./home-assistant.nix
#      ../config/home-manager.nix # get working
    ];

  # Use the systemd-boot EFI boot loader.
  boot = {
    kernelModules = [ "wl" ];
    blacklistedKernelModules = [ "b43" "bcma" ];
    extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
  };

  networking.hostName = "sauron"; # Define your hostname.
  networking.hostId = "acfb04f9"; # head -c 8 /etc/machine-id

  networking.networkmanager.enable = false;  # Easiest to use and most distros use this by default.
  networking.interfaces = {
    eno2 = {
        mtu = 9000;
    };
  };

  # firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22 # ssh via tailscale
      27015 # steam
    ];
    allowedUDPPorts = [
      config.services.tailscale.port
      27015 # steam
    ];
    # always allow traffic from your Tailscale network
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };

  ## services
  services.tailscaleAuth = {
    enable = true;
  };

  users.groups.emma = {};
  users.users = {
    emma = {
      isSystemUser = true;
      group = "emma";
    };
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    ipmiutil
    ipmitool
    steamcmd
    docker # todo - replace with podman
  ];

  # enable docker support
  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };

  services.openssh = {
    # support yubikey
    # https://developers.yubico.com/SSH/Securing_SSH_with_FIDO2.html
    extraConfig = ''
    PubkeyAuthOptions verify-required
  '';
  };

  services.tailscale.authKeyFile = config.age.secrets.tailscale-authkey.path;

  # secrets
  age = {
    identityPaths = ["/srv/vault/ssh_keys/id_rsa"]; # requires `/srv/vault` to be mounted before agenix can be used
    secrets = {
      tailscale-server = {
        file = ../../secrets/tailscale-server.age;
      };
      tailscale-authkey = {
        file = ../../secrets/tailscale-authkey.age;
      };
    };
  };

  # does not support automatic merging so cannot put these into modules
  nixpkgs.config.permittedInsecurePackages = [
    # for jackett
    "dotnet-sdk-6.0.428"
    "aspnetcore-runtime-6.0.36"
    # maubot
    "olm-3.2.16"
    # home-assistant
    "openssl-1.1.1w"
  ];

  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}

