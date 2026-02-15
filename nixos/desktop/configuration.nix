{
  pkgs,
  config,
  ...
}: {
  imports = [
    ../config/common
    ../config/network
    ../config/network/nfs_mounts.nix
    ../config/home-manager.nix
    ../config/overclocking.nix
    ../config/desktop-common.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "desktop"; # Define your hostname.
  networking.hostId = "cc74da59";

  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  networking.firewall.enable = false;

  # Fixing time sync when dualbooting with Windows
  time.hardwareClockInLocalTime = true;

  # https://github.com/NixOS/nixpkgs/blob/26d499fc9f1d567283d5d56fcf367edd815dba1d/pkgs/os-specific/linux/kernel/kernels-org.json
  # boot.kernelPackages = pkgs.linuxPackages_6_16;

  hardware.amdgpu.initrd.enable = true;

  # https://nixos.wiki/wiki/AMD_GPU
  services.xserver.videoDrivers = ["amdgpu"];

  # Enable OpenGL
  hardware.graphics = with pkgs; {
    enable = true;
    enable32Bit = true;
    package = unstable.mesa;
    package32 = unstable.driversi686Linux.mesa;
  };

  # ssh-keyscan $hostname
  age.rekey.hostPubkey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCzy08KRm3Dg4Re2zW74CQ7XaqFo8AG85m0QSS49C4QU76UATSkKsxjqoPSHtCA2BG+8DUkm9O8XR3UZ5x37F4oW3mwYC6Hj4FdBmbgEQ3GmBQv+qMgwSCKLEsbaQVQUIGCDZ/urCJrizsxBbFu2gJpzCpcxTfx+q0f93QgOLd5/pKsh/fNKehwFtR59fZRMiVw5W6PTPCVVMgqSlchBk0x7x9f/V1SJVfqf023ywRXNKXmz5D2nUQwSsCfktXoo7F4r1oaFsnip+oRsy1/h/hry8f54QR1s3iEYwLhbgrZiI/ZzntApXyP/vT5SO5MEulGktnQHYkQxd+b28IJsYjWwbMDF6GD1NQlpYoyMWVjNDMppdk1o+Qlabxt5QgZar5wmqLrAgAMMrPM1NEg3qKPIYxNV7ntYwtMwRGigffJQLSf68u1RvNxPaew6TxlzN1TWaJYWcjmaqY1hk+bMY4GHw9UoZbedtq7XAP+u/yzFjtLLOgwmfzxmSq72YEsKV9IF8uB0fuwbr+8kXxjxscSys95SwiFJtqVOJW6RucnFXYIStI0pWCrZLvqUdYnMnmFlBoL0TVX+P99RXZv//Tjfz5wi8HyFApmOOVb5eTQmbMdV8hJTAYXf6qdC4WMcPtkaAH+PgznGCyEp1zG7P0vaf6LHQ2jhAyBszHihGAhjQ==";

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
          id = "5ATZ7LD-C3AYIMS-EXQZILG-2A743HY-4Y7ULQY-RODJR7F-GO43W6X-CLXDAAA";
        };
      };
    };
  };
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
