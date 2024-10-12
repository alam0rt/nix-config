# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [
      ../config/zfs.nix
      ../config/nvidia.nix
      ../config/home-manager.nix
      ./hardware-configuration.nix
    ];

  networking.hostName = "desktop"; # Define your hostname.
  networking.hostId = "cc74da59";
  # Pick only one of the below networking options.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
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
        "banshee"   = { id = "S5V7OMM-KMCFGTF-DI2X72J-QNY565R-XBWZERU-MH6LCDV-QLTSNYJ-FKJ47A2"; };
        "Pixel 6"   = { id = "OR72TPR-WG5BLKK-SNQGHEG-SEFVF5U-R4SSWWC-WO4EVTE-6DZ6GCZ-3SMARA7"; };
        "sanic"     = { id = "AAIAFMS-YQUTFOU-OYA7SKU-HLRDNIH-MB7XKNF-RPHT2GN-ZEIFHYC-U7NYGQ5"; };
      };
    };
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    extraUpFlags = ["--login-server=https://hs.samlockart.com"];
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
    desktopManager = {
      xterm.enable = false;
      xfce.enable = true;
    };
  };
 # services.displayManager.defaultSession = "xfce";

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # core
    vim
    firefox
    kitty
    
    # social
    mumble
    gnupg

    # dev
    ghidra

    # fun
    lutris
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
}

