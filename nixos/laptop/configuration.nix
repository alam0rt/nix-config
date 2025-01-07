# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ inputs, pkgs, ... }:

{
  imports =
    [
      ../config/zfs.nix
      ../config/nvidia-patch.nix
      ../config/home-manager.nix
      ./hardware-configuration.nix
    ];

  networking.hostName = "laptop"; # Define your hostname.
  networking.hostId = "deadbabe";
  # Pick only one of the below networking options.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  networking.firewall = {
    enable = true; # do i really need this??
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
    allowedTCPPorts = [
      8384 22000 # syncthing
      22 # ssh via tailscale
    ];
    allowedUDPPorts = [];
  };

  # Syncthing
  services.syncthing = {
    enable = true;
    user = "sam";
    dataDir = "/home/sam/vault";    # Default folder for new synced folders
    configDir = "/home/sam/.config/syncthing";   # Folder for Syncthing's settings and keys
    guiAddress = "http://127.0.0.1:8384";
    settings = {
      devices = {
        "laptop"   = { id = "S5V7OMM-KMCFGTF-DI2X72J-QNY565R-XBWZERU-MH6LCDV-QLTSNYJ-FKJ47A2"; };
        "desktop"   = { id = "F7G62MY-FWFWFNY-PYVBZQE-S4EXYDX-IIPF4AQ-YAKJVP3-4TZXCKT-NAUTJQU"; };
      };
    };
  };

  # networking
  services.tailscale = {
    enable = true;
    openFirewall = true;
    extraUpFlags = ["--login-server=https://hs.samlockart.com"];
  };

  programs.wireshark = {
    enable = true;
  };

  fileSystems."/mnt/share/sam" = {
    device = "sauron:/srv/share/sam";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" ];
  };

  fileSystems."/mnt/share/public" = {
    device = "sauron:/srv/share/public";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" ];
  };

  fileSystems."/mnt/media/downloads" = {
    device = "sauron:/srv/media/downloads";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" ];
  };

  fileSystems."/mnt/media/tv" = {
    device = "sauron:/srv/media/tv";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" ];
  };

  fileSystems."/mnt/media/movies" = {
    device = "sauron:/srv/media/movies";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" ];
  };
  
  # Enable the X11 windowing system.
  services.xserver = {
    enable = true;
    xkb.layout = "us";
    videoDrivers = ["i915"];
    desktopManager = {
      xterm.enable = false;
      xfce.enable = true;
    };
  };
  services.displayManager.defaultSession = "xfce";

  hardware.nvidia.prime = {
    nvidiaBusId = "PCI:1:0:0";
    intelBusId = "PCI:0:2:0";
    sync.enable = true;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # core
    vim
    firefox
    
    # social
    mumble
    element
    gnupg

    # dev
    ghidra
    wireshark
    wineWowPackages.stable

    # fun
    unstable.lutris
    unstable.shadps4

    # 3d
    super-slicer-latest
  ];

  # bluetooth
  services.blueman.enable = true;
  hardware.bluetooth.enable = true; # enables support for Bluetooth
  hardware.bluetooth.powerOnBoot = true; # powers up the default Bluetooth controller on boot

  # steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
 #   localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
  };

  services.smartd = {
    enable = true;
  };

  nixpkgs.overlays = [inputs.nvidia-patch.overlays.default];

  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
