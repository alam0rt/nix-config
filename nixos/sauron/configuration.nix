# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  config,
  pkgs,
  ...
}: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../config/common
    ../config/network
    ../config/nvidia.nix
    ../config/zfs.nix
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
    #./k8s.nix
    #      ../config/home-manager.nix # get working
  ];
  # Use the systemd-boot EFI boot loader.
  boot = {
    kernelModules = ["wl"];
    blacklistedKernelModules = [
      "b43"
      "bcma"
    ];
    # insecure and wireless not used
    # extraModulePackages = [config.boot.kernelPackages.broadcom_sta];
  };

  networking.hostName = "sauron"; # Define your hostname.
  networking.hostId = "acfb04f9"; # head -c 8 /etc/machine-id

  networking.networkmanager.enable = false; # Easiest to use and most distros use this by default.
  networking.interfaces = {
    eno2 = {
      mtu = 9000;
    };
  };

  networking.firewall.enable = true;

  ## services
  services.tailscaleAuth = {
    enable = true;
  };

  systemd.slices = {
    # todo: use substitution
    "user-${toString config.users.users.raf.uid}" = {
      overrideStrategy = "asDropin";
      # https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html
      sliceConfig = {
        "CPUWeight" = "20";
        "CPUQuota" = "3200%"; # out of 6400%
        "MemoryHigh" = "32G";
        "MemoryMax" = "40G";
        "TasksMax" = "2048";
      };
    };
  };

  users.groups.emma = {};
  users.groups.raf = {};
  users.groups.chowder = {};
  users.users = {
    emma = {
      isSystemUser = true;
      group = "emma";
    };
    chowder = {
      isSystemUser = true;
      group = "chowder";
    };
    raf = {
      packages = with pkgs; [
        git
        nano
        zlib

        gatk # genotyping
        (trimmomatic.override { jre = pkgs.jdk11; }) # fails with jdk21
        samtools
        picard-tools
        bamtools
        angsd
        hmmer
        muscle
        sickle
        blast
        bowtie2
      ];
      uid = 1003; # for persistence
      isNormalUser = true;
      shell = pkgs.zsh;
      group = "raf";
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCWFtj8xaCsRMvu3WE1T+z486LQXvWYRUTpk1V1JS0uZ3N1A6oaDM3NPIcktontQMRnq42b0l5RA2J/B3N/TNHyeoWXkeDD/qinv/KFSChf8WYaEk7VLpFJoxvrTEvETeqIzwDLL+A7/hLGDt9Uq2uVxj1AdKU8oWbYVj5+qHs/yOqTEqngYcc0RSngnz0BySbl9+S4/PTxdnFk6z5cQxGmlGP0CG3KAYgN3YghY+7ykRqQZ8Xi5+v4TOdHx/JYXF5CHdIJjRjT0CEdQYLA+esAfjZ7ZdirHiIrp8+QrcV1E7fOlbiZq5ieYDu6KOD4EOUKiWjLma0VUKLV5Jj/xAy1+P5t3xbXDF+K9Gg3gLTWGg2uaMOw2R+arraN879wVKcmz3QhYd1lnotfUtMslI2QoqSvdnZJSrKeqMpTUOHs57IREvJpOCkybwKXj9LPVeGn4Jg2C1hjHdCksQQmUkbJLYZ77BK6qpb9H3d478yI41TM/XWQPaoRtKspi7goTlU= apomys@edgar"
      ];
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
    settings = {
      PrintMotd = true;
    };
    banner = ''
      speak friend and enter...
    '';
    openFirewall = true;
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
