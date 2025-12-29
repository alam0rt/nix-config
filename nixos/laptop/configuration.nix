{
  inputs,
  pkgs,
  config,
  ...
}: {
  imports = [
    ../config/common
    ../config/network
    ../config/network/nfs_mounts.nix
    ../config/nvidia.nix
    ../config/home-manager.nix
    ../config/desktop-common.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "laptop"; # Define your hostname.
  networking.hostId = "deadbabe";

  # Pick only one of the below networking options.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  networking.wireless.userControlled.enable = true;

  networking.firewall.enable = true;

  # ssk-keyscan $hostname
  age.rekey.hostPubkey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQD1T9mW39qktiMSPdx6f1J88poTg02UebSLlzwSP/F3mO5TUVShFomeS2lto0BgFul9tVvxxCN582Kh604nFQ/gq59wew4d9N96c0l2c584gj3sfg8O1xxkPsFa+EPZ98JGBpuLiYvzzGguUeITSE+uP4jyJ4EPEn55NwnJx74uCGGaFt3D2dCAF99jWCKWvvWR1Wk0znW18RDm9kOvlXflAJ02s2+Vne/PWiaOVm6Kw+/JAaRCxxncTyf7LFnzXAPOvVmdYzNgKFsN36r7A9CTRgDhWqXFkZBwoWS8PIDxS9iwLaapNv3kMAfJXx8UxZYLPx+Jbi0Q88JaSvnmqMJwP1BwsXoEoadWzY+oEXr9MJ1K2Q2dyyl6ZAoEgU4A5dBcmc0E14mltgD/09JJDMhf5HWzwRQXoo/ZSQ0+lTmNwQDrYaomuBayaKbECNki5J2NjGMICtHmGVzeLxzHZnBnAGxmURE90rXvy5gKF7nruVFmcViEnzzUqPweemcwsSmNhx0TSJfrqHRs4+rsJlAJ0JZTVE1fYVHqCbe7x13dUTpMChHHy0NPvwfao/EPC05fJAypTSr/5a76qf/lh58Ahmxg5HpbOx8RbasfKwkJTT0Kg58sexia8CUsTdl2u/YknyB4z0uXxlvtooa702/3WXf9oUNI71wfXi4k+pBKxw==";

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

  # audio
  services.pipewire.enable = true;
  services.pipewire.pulse.enable = true;
  security.rtkit.enable = true;

  # steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
  };

  programs.ghidra = {
    enable = true;
    package = let
      ghidraWithExts = pkgs.ghidra.withExtensions (p: with p; [
        ret-sync
        findcrypt
      ] ++ [ pkgs.ghidra-psx-ldr ]);
    in pkgs.symlinkJoin {
      name = "ghidra-wrapped";
      paths = [ ghidraWithExts ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/ghidra --set _JAVA_AWT_WM_NONREPARENTING 1
      '';
    };
  };

  nixpkgs.overlays = [inputs.nvidia-patch.overlays.default];

  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
