{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ../config/common
    ../config/network
    ../config/network/nfs_mounts.nix
    ../config/nvidia.nix
    ../config/home-manager.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "laptop"; # Define your hostname.
  networking.hostId = "deadbabe";

  # Pick only one of the below networking options.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  networking.wireless.userControlled.enable = true;

  networking.firewall.enable = true;



  # Syncthing
  services.syncthing = {
    enable = true;
    user = "sam";
    dataDir = "/home/sam/vault"; # Default folder for new synced folders
    configDir = "/home/sam/.config/syncthing"; # Folder for Syncthing's settings and keys
    guiAddress = "http://127.0.0.1:8384";
    settings = {
      devices = {
        "laptop" = {
          id = "S5V7OMM-KMCFGTF-DI2X72J-QNY565R-XBWZERU-MH6LCDV-QLTSNYJ-FKJ47A2";
        };
        "desktop" = {
          id = "F7G62MY-FWFWFNY-PYVBZQE-S4EXYDX-IIPF4AQ-YAKJVP3-4TZXCKT-NAUTJQU";
        };
      };
    };
  };

  programs.wireshark = {
    enable = true;
  };

  # reduce power consumption
  services.xserver.videoDrivers = ["i915"];

  # platformio / embedded dev
  services.udev.packages = with pkgs; [
    platformio-core.udev
    openocd
  ];

  # enable prime
  hardware.nvidia.prime = {
    nvidiaBusId = "PCI:1:0:0";
    intelBusId = "PCI:0:2:0";
    sync.enable = true;
  };

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

  programs.ghidra.enable = true;

  nixpkgs.overlays = [inputs.nvidia-patch.overlays.default];

  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
