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

  networking.hostName = "desktop"; # Define your hostname.
  networking.hostId = "cc74da59";
  # Pick only one of the below networking options.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  networking.firewall = {
    enable = false; # do i really need this??
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
    allowedTCPPorts = [
      8384 22000 # syncthing
      22 # ssh via tailscale
      6112 # wc3
    ];
    allowedUDPPorts = [
      6112
    ];
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
        "laptop"   = { id = "5ATZ7LD-C3AYIMS-EXQZILG-2A743HY-4Y7ULQY-RODJR7F-GO43W6X-CLXDAAA"; };
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

  services.avahi = {
    enable = true;
    reflector = true;
    allowInterfaces = ["tailscale0" "enp4s0" ];
    allowPointToPoint = true;
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
    videoDrivers = ["nvidia"];
    desktopManager = {
      xterm.enable = false;
      xfce.enable = true;
    };
  };
 # services.displayManager.defaultSession = "xfce";
  programs.nix-ld.enable = true;

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

    # misc
    calibre
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

  # open source NVIDIA game streaming service
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
    
  };

  # VR streaming
  programs.alvr = with pkgs; {
    enable = true;
    openFirewall = true;
    package = unstable.alvr;
  };

  services.smartd = {
    enable = true;
  };

  services.flatpak.enable = true;
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-gtk];

  nixpkgs.overlays = [inputs.nvidia-patch.overlays.default];

  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}

