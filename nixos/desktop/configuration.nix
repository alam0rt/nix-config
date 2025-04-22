# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ inputs, pkgs, ... }:

{
  imports =
    [
      ../config/graphical
      ../config/common
      ../config/network
      ../config/home-manager.nix
      ../config/llm.nix
      ./hardware-configuration.nix
    ];

  networking.hostName = "desktop"; # Define your hostname.
  networking.hostId = "cc74da59";
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.
  networking.firewall.enable = false;

  # 9070 xt requires >= 6.13.5
  # latest currently points to 6.13.11
  # https://github.com/NixOS/nixpkgs/blob/26d499fc9f1d567283d5d56fcf367edd815dba1d/pkgs/os-specific/linux/kernel/kernels-org.json
  boot.kernelPackages = pkgs.unstable.linuxPackages_latest;

  # https://nixos.wiki/wiki/AMD_GPU
  boot.initrd.kernelModules = [ "amdgpu" ];
  services.xserver.videoDrivers = [ "modesetting" ];

  # Enable OpenGL
  hardware.graphics = with pkgs; {
    enable = true;
    enable32Bit = true;
    # mesa 25 at time of comment
    # https://translate.kagi.com/translate/https://www.overclockers.at/grafikkarten/probleme-mit-9070-xt-ubuntu-24-04_264796
    #package = unstable.mesa;
    #package32 = unstable.driversi686Linux.mesa;
  };

  # secrets
  age = {
    # TODO: will cause issues as syncthing needs to sync this before we can decrypt
    identityPaths = ["/home/sam/vault/ssh_keys/id_rsa"];
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

  programs.wireshark.enable = true;

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
    wireshark
    wineWowPackages.stable
    winetricks

    # fun
    unstable.lutris
    unstable.shadps4
    r2modman

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
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
  };


  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}

