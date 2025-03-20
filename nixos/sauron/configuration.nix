# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../config/common
      ../config/network
      ../config/nvidia.nix
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
      2049 # nfsv4
      111 2049 4000 4001 4002 20048 # nfs
      9091 # transmission RPC
      8384 22000 # syncthing
      5357 # wsdd - samba
      445 # samba
      config.services.murmur.port # murmur
      80 443 8080 8443 # nginx
      8081 8444 # unifi
      22 # ssh via tailscale
      27015 # steam
      23916 # maubot
      51413 # torrent
      8191 # flaresolverr
    ];
    allowedUDPPorts = [
      111 2049 4000 4001 4002 20048 # nfs
      22000 21027 # syncthing
      config.services.murmur.port # murmur
      3702 # wsdd - samba
      config.services.tailscale.port
      27015 # steam
      51413 # torrent
      3478 # unifi
      1900 7359 # dlna jellyfin
    ];
    # always allow traffic from your Tailscale network
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };

  ## services
  services.tailscaleAuth = {
    enable = true;
  };

  # https://nixos.org/manual/nixos/stable/#module-services-prometheus-exporters
  services.prometheus.exporters.node = {
    enable = false;
    port = 9000;
    # https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/services/monitoring/prometheus/exporters.nix
    enabledCollectors = [ "systemd" ];
    # /nix/store/zgsw0yx18v10xa58psanfabmg95nl2bb-node_exporter-1.8.1/bin/node_exporter  --help
    extraFlags = [ "--collector.ethtool" "--collector.softirqs" "--collector.tcpstat" "--collector.wifi" ];
  };

  services.prometheus = {
    enable = false;
    globalConfig.scrape_interval = "10s"; # "1m"
    scrapeConfigs = [
    {
      job_name = "node";
      static_configs = [{
        targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ];
      }];
    }
    ];
  }; 

  services.nginx = {
    enable = true;

    # recommended settings
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    # Only allow PFS-enabled ciphers with AES256
    sslCiphers = "AES256+EECDH:AES256+EDH:!aNULL";

    # whitelisting
    commonHttpConfig = ''
    #allow 192.168.0.0/24;
    #allow 10.0.0.0/16;
    #allow 173.245.48.0/20;
    #allow 103.21.244.0/22;
    #allow 103.22.200.0/22;
    #allow 103.31.4.0/22;
    #allow 141.101.64.0/18;
    #allow 108.162.192.0/18;
    #allow 190.93.240.0/20;
    #allow 188.114.96.0/20;
    #allow 197.234.240.0/22;
    #allow 198.41.128.0/17;
    #allow 162.158.0.0/15;
    #allow 104.16.0.0/13;
    #allow 104.24.0.0/14;
    #allow 172.64.0.0/13;
    #allow 131.0.72.0/22;
    #deny all;

    # Add HSTS header with preloading to HTTPS requests.
    # Adding this header to HTTP requests is discouraged
    map $scheme $hsts_header {
        https   "max-age=31536000; includeSubdomains; preload";
    }
    add_header Strict-Transport-Security $hsts_header;

    # Enable CSP for your services.
    #add_header Content-Security-Policy "script-src 'self'; object-src 'none'; base-uri 'none';" always;

    # Minimize information leaked to other domains
    add_header 'Referrer-Policy' 'origin-when-cross-origin';

    # Disable embedding as a frame
    # breaks jellyfin on webOS
    # https://jellyfin.org/docs/general/networking/nginx/
    # - saml
    # add_header X-Frame-Options DENY;

    # Prevent injection of code in other mime types (XSS Attacks)
    add_header X-Content-Type-Options nosniff;

    # Enable XSS protection of the browser.
    # May be unnecessary when CSP is configured properly (see above)
    add_header X-XSS-Protection "1; mode=block";

    # This might create errors
    proxy_cookie_path / "/; secure; HttpOnly; SameSite=strict";

    # Default is far too small
    client_max_body_size 500M;
    '';

    virtualHosts."tv.samlockart.com" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
      };
    };
    virtualHosts."tv.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
      };
    };
    virtualHosts."pass.iced.cool" = {
      # https://github.com/dani-garcia/vaultwarden/wiki/Deployment-examples#nixos-by-tklitschi
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.vaultwarden.config.ROCKET_PORT}";
        recommendedProxySettings = true;
      };
    };
    virtualHosts."www.iced.cool" = {
      # catch all
      forceSSL = true;
      enableACME = true;
      default = true;
      locations."/" = {
        return = 404;
      };
    };
    virtualHosts."open-webui.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.open-webui.port}";
        recommendedProxySettings = true;
      };
    };
    virtualHosts.${toString config.services.grafana.settings.server.domain} = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "${toString config.services.grafana.settings.server.protocol}://${toString config.services.grafana.settings.server.http_addr}:${toString config.services.grafana.settings.server.http_port}";
        recommendedProxySettings = true;
        proxyWebsockets = true;
      };
    };
    tailscaleAuth = {
      enable = true;
      virtualHosts = [
        config.services.grafana.settings.server.domain
        "jackett.middleearth.samlockart.com"
      ];
    };
    virtualHosts."sonarr.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8989";
      };
    };
    virtualHosts."jackett.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:9117";
      };
    };
    virtualHosts."bazarr.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.bazarr.listenPort}";
      };
    };
    virtualHosts."radarr.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:7878";
      };
    };
    virtualHosts."sync.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8384";
      };
    };
    virtualHosts."transmission.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:9091";
      };
    };
  };
  # accept the EULA
  security.acme.defaults.email = "sam@samlockart.com";
  security.acme.acceptTerms = true;
  

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  users.groups.emma = {};
  users.users = {
    emma = {
      isSystemUser = true;
      group = "emma";
    };
    # sftp
    chowder = {
      isNormalUser = true;
      shell = "/usr/bin/nologin";
      group = "sftponly";
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDXa9yFKcUaD631H81iDvGao7anXq0/cOFIJ3zI0I39+Evgzt2rsaJbp6kgCthgwg/pTVIXsh5WGERL33/HsygbtR0Jy3JlXUsb8lwS83T5L3scL1Z6KfkoABGMwbCA9yyBZWiRtZU6zYAtXCwIytBzkTgvCic5yaN94io75e+Sj0nKxPlHP50f8yZTcHLUCexTg7aBDptqEzo8rPeKg0YSjlSlyPs5CR8OGluQlJsNIw2dzIGzeT4aTXMTO55YhGGHweD29gT1r3pp4nhRYdTUuU5R1gYevCD/Ok1W58aL6spS8z2fAMm6YMPeme8dRUEZ018Qow3lDHbQ3CaZfZYFuxRXTYLIWG6eHJyS/1H95nF9YfF+f9iA+jyvcXGEooPm8SPXM84eOMSZrzCbtQHYvslLqws/CYX/gxoIASWeGbJvqwM3esSj5m9X/qy6dsGJjDCXZKr8bcqoN33yW6YTi7hzoUSfgcOMjlv9peEiEiMciaFn2XE1GtcHi4G1hPk="
      ];
      
    };
    # services
    syncthing = {
      isSystemUser = true;
      group = "syncthing";
    };
    nginx = {
      isSystemUser = true;
      extraGroups = ["murmur"];
    };
    unifi = {
      isSystemUser = true;
      group = "unifi";
    };
  };
  users.groups = {
    sftponly = {};
    unifi = {};
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    borgbackup
    ipmiutil
    ipmitool
    steamcmd
    mailutils
    unstable.jellyfin
    unstable.jellyfin-web
    unstable.jellyfin-ffmpeg
    docker # todo - replace with podman
  ];

  services.pvpgn = {
    enable = true;
    bnetd = {
      servername = "WankNet";
      logFile = "/var/log/bnetd.log";
    };
    localStateDir = "/srv/data/pvpgn";
    openFirewall = true;
    news = ''
      {2024-10-16}

      Welcome to the jungle.
    '';
  };

  # enable docker support
  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };

  # selfhosted rarbg
  # https://github.com/mgdigital/rarbg-selfhosted
  virtualisation.oci-containers.containers = {
    rarbg = {
      image = "ghcr.io/mgdigital/rarbg-selfhosted:latest";
      ports = ["3333:3333"];
      volumes = ["/srv/data/rarbg_db.sqlite:/rarbg_db.sqlite"];
    };

    maubot = {
      image = "dock.mau.dev/maubot/maubot";
      ports = ["29316:29316"];
      volumes = ["/srv/data/maubot:/data:z"];
      extraOptions = ["--network=host"];
    };

    flaresolverr = {
      image = "ghcr.io/flaresolverr/flaresolverr:latest";
      ports = ["8191:8191"];
    };

    unifi = {
      image = "jacobalberty/unifi";
      ports = ["8081:8081" "8444:8444" "3478:3478/udp"];
      user = "unifi:unifi";
      volumes = ["/srv/data/unifi:/unifi"];
      environment = {
        TZ = "Australia/Melbourne";
        UNIFI_HTTP_PORT = "8081";
        UNIFI_HTTPS_PORT = "8444";
      };
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };
  programs.msmtp = {
    enable = true;
    setSendmail = true;
    defaults = {
      aliases = "/etc/aliases";
      port = 465;
      tls_trust_file = "/etc/ssl/certs/ca-certificates.crt";
      tls = true;
      auth = "login";
      tls_starttls = "off";
    };
    accounts = {
      default = {
        host = "smtp.sendgrid.com";
	tls_fingerprint = "3F:C8:AD:FE:3F:20:7F:D9:90:F4:9D:56:14:64:DE:97:A4:64:F7:3B:2F:AE:FD:0D:74:94:22:CF:A2:F5:A8:01";
        passwordeval = "cat /srv/data/secrets/sendgrid";
        user = "apikey";
        from = "sauron@samlockart.com";
      };
    };
  };
  environment.etc = {
    "aliases" = {
	text = ''
	root: sam@samlockart.com
	'';
	mode = "0644";
    };
  };

  # List services that you want to enable:
  services.unifi = {
    enable = false;
    unifiPackage = pkgs.unifi7;
    mongodbPackage = pkgs.mongodb-5_0; # cannot compile mongo so disabling
  };

  # Enable the OpenSSH daemon.
  services.openssh = {
    # support yubikey
    # https://developers.yubico.com/SSH/Securing_SSH_with_FIDO2.html
    extraConfig = ''
    PubkeyAuthOptions verify-required
    Match Group sftponly
      ChrootDirectory /srv/share/public
      ForceCommand internal-sftp
      AllowTcpForwarding no
  '';
  };

  # Samba
  services.samba-wsdd.enable = true; # make shares visible for windows 10 clients
  # networking.firewall.allowedTCPPorts = [
  #   5357 # wsdd
  # ];
  # networking.firewall.allowedUDPPorts = [
  #   3702 # wsdd
  # ];
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "sauron";
        "netbios name" = "sauron";
        security = "user";
        "hosts allow" = "100.64. 192.168.0. 127.0.0.1 localhost ::1";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
      public = {
        path = "/srv/share/public";
        browseable = "yes";
        writable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0664";
        "directory mask" = "2777";
        "force user" = "nobody";
        "force group" = "nogroup";
      };
      sam = {
        path = "/srv/share/sam";
        browseable = "no";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0600";
        "directory mask" = "0700";
        "force user" = "sam";
        "force group" = "root";
      };
      emma = {
        path = "/srv/share/emma";
        browseable = "no";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0600";
        "directory mask" = "0700";
        "force user" = "emma";
        "force group" = "root";
      };
      tv = {
        path = "/srv/media/tv";
        browseable = "yes";
        "read only" = "yes";
        "guest ok" = "yes";
        "create mask" = "0600";
        "directory mask" = "0700";
        "force user" = "nobody";
        "force group" = "nogroup";
      };
      movies = {
        path = "/srv/media/movies";
        browseable = "yes";
        "read only" = "yes";
        "guest ok" = "yes";
        "create mask" = "0600";
        "directory mask" = "0700";
        "force user" = "nobody";
        "force group" = "nogroup";
      };
      downloads = {
        path = "/srv/media/downloads";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "nobody";
        "force group" = "nogroup";
      };
    };
  };

  # monitoring
  # grafana configuration
  services.grafana = {
    enable = false;
    settings = {
        server = {
          domain = "grafana.middleearth.samlockart.com";
          root_url = "http://${toString config.services.grafana.settings.server.domain}/";
          protocol = "https";
          http_port = 3000;
          http_addr = "127.0.0.1";
          serve_from_sub_path = false;
        };
    };
  };

  # NFS
  services.nfs.server = {
    enable = true;
    # fixed rpc.statd port; for firewall
    lockdPort = 4001;
    mountdPort = 4002;
    statdPort = 4000;
    exports = ''
      /srv/share/sam          192.168.0.0/255.255.255.0(rw,fsid=0,no_subtree_check) 100.64.0.0/255.255.255.0(rw,fsid=0,no_subtree_check)
      /srv/share/emma         192.168.0.0/255.255.255.0(rw,fsid=0,no_subtree_check) 100.64.0.0/255.255.255.0(rw,fsid=0,no_subtree_check)
      /srv/share/public       192.168.0.0/255.255.255.0(rw,nohide,insecure,no_subtree_check) 100.64.0.0/255.255.255.0(rw,nohide,insecure,no_subtree_check)
      /srv/media              192.168.0.0/255.255.255.0(ro,nohide,insecure,no_subtree_check) 100.64.0.0/255.255.255.0(rw,nohide,insecure,no_subtree_check)
  '';
  };
  services.vaultwarden = {
    enable = true;
    backupDir = "/srv/data/vaultwarden";
    config = {
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      DOMAIN = "https://pass.iced.cool";
      SIGNUPS_ALLOWED = false; # sorry lads :^)
    };
  };

  services.open-webui = {
    enable = true;
    openFirewall = true;
    port = 11111;
    environment = {
      OLLAMA_API_BASE_URL = "http://desktop:11434";
    };
  };

  # Syncthing
  services.syncthing = {
    enable = true;
    user = "syncthing";
    dataDir = "/srv/vault";    # Default folder for new synced folders
    configDir = "/srv/data/syncthing";   # Folder for Syncthing's settings and keys
    overrideDevices = true;     # overrides any devices added or deleted through the WebUI
    overrideFolders = true;     # overrides any folders added or deleted through the WebUI
    guiAddress = "http://0.0.0.0:8384";
    settings = {
      # TODO: use declarative node configuration
      # https://wiki.nixos.org/wiki/Syncthing
      devices = {
        "laptop"   = { id = "5ATZ7LD-C3AYIMS-EXQZILG-2A743HY-4Y7ULQY-RODJR7F-GO43W6X-CLXDAAA"; };
        "desktop"   = { id = "F7G62MY-FWFWFNY-PYVBZQE-S4EXYDX-IIPF4AQ-YAKJVP3-4TZXCKT-NAUTJQU"; };
      };
      folders = {
        "vault" = {        # Name of folder in Syncthing, also the folder ID
           path = "/srv/vault";    # Which folder to add to Syncthing
           devices = [ "laptop" "desktop" ];      # Which devices to share the folder with
        };
      };
    };
  };

  ## backup
  services.borgbackup.jobs = {
    mordor-vault = {
      paths = "/srv/vault";
      repo = "20972@hk-s020.rsync.net:mordor/vault";
      doInit = true;
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.age.secrets.borg.path}";
      };
      environment.BORG_RSH = "ssh -i /srv/vault/ssh_keys/id_rsa";
      compression = "auto,zstd";
      startAt = "daily";
    };
   mordor-srv-data = {
      paths = "/srv/data";
      repo = "20972@hk-s020.rsync.net:mordor/srv/data";
      doInit = true;
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.age.secrets.borg.path}";
      };
      environment.BORG_RSH = "ssh -i /srv/vault/ssh_keys/id_rsa";
      compression = "auto,zstd";
      startAt = "daily";
    };
   mordor-share-sam = {
      paths = "/srv/share/sam";
      repo = "20972@hk-s020.rsync.net:mordor/share/sam";
      doInit = true;
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.age.secrets.borg.path}";
      };
      environment.BORG_RSH = "ssh -i /srv/vault/ssh_keys/id_rsa";
      compression = "auto,zstd";
      startAt = "daily";
    };
   mordor-share-emma = {
      paths = "/srv/share/emma";
      repo = "20972@hk-s020.rsync.net:mordor/share/emma";
      doInit = true;
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.age.secrets.borg.path}";
      };
      environment.BORG_RSH = "ssh -i /srv/vault/ssh_keys/id_rsa";
      compression = "auto,zstd";
      startAt = "daily";
    };
  };

  ## alert on failure
  systemd.services = {
    "notify-problems@" = {
      enable = false; # need to fix sendgrid shit
      serviceConfig.User = "root";
      environment.SERVICE = "%i";
      script = ''
        printf "Content-Type: text/plain\r\nSubject: $SERVICE FAILED\r\n\r\n$(systemctl status $SERVICE)" | /run/wrappers/bin/sendmail root
      '';
    };
  };
  systemd.packages = [
    (pkgs.runCommandNoCC "notify.conf" {
      preferLocalBuild = true;
      allowSubstitutes = false;
    } ''
      mkdir -p $out/etc/systemd/system/service.d/
      echo -e "[Unit]\nOnFailure=notify-problems@%i.service\nStartLimitIntervalSec=1d\nStartLimitBurst=5\n" > $out/etc/systemd/system/service.d/notify.conf
      '')
  ];


  services.transmission = {
    enable = true;
    credentialsFile = config.age.secrets.transmission-credentials.path;
    settings = {
      home = "/srv/data/transmission";
      download-dir = "/srv/media/downloads";
      incomplete-dir = "/srv/media/downloads/.incomplete";
      trash-original-torrent-files = true;
      rpc-bind-address = "0.0.0.0";
      rpc-port = 9091;
      rpc-whitelist = "127.0.0.1,192.168.0.*,100.64.0.*";
      rpc-host-whitelist-enabled = false;
      rpc-authentication-required = false;
      ratio-limit = "0.0";
      ratio-limit-enabled = true;
    };
  };

  systemd.timers."transmission-restart" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1h";
      OnUnitActiveSec = "1h";
      Unit = "transmission-restart.service";
    };
  };

  systemd.services."transmission-restart" = {
    script = ''
      set -eu
      ${pkgs.systemd}/bin/systemctl restart transmission.service
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  services.jellyfin = {
    package = pkgs.unstable.jellyfin;
    enable = true;
    openFirewall = true;
    dataDir = "/srv/data/jellyfin";
    cacheDir = "/var/cache/jellyfin"; # leave on ssd
  };

  services.radarr = {
    enable = true;
    dataDir = "/srv/data/radarr";
    openFirewall = true;
  };
  users.users.radarr.extraGroups = ["transmission"];

  services.sonarr = {
    enable = true;
    dataDir = "/srv/data/sonarr";
    openFirewall = true;
  };
  users.users.sonarr.extraGroups = ["transmission"];

  services.jackett = {
    enable = true;
    dataDir = "/srv/data/jackett";
    package = pkgs.unstable.jackett;
    openFirewall = true;
  };

  services.bazarr = {
    enable = true;
    openFirewall = true;
  };
  users.users.bazarr.extraGroups = ["sonarr" "radarr"];

  services.tailscale.authKeyFile = config.age.secrets.tailscale-authkey.path;

  # secrets
  age = {
    identityPaths = ["/srv/vault/ssh_keys/id_rsa"]; # requires `/srv/vault` to be mounted before agenix can be used
    secrets = {
      borg = {
        file = ../../secrets/borg.age;
      };
      tailscale-server = {
        file = ../../secrets/tailscale-server.age;
      };
      tailscale-authkey = {
        file = ../../secrets/tailscale-authkey.age;
      };
      transmission-credentials = {
        file = ../../secrets/transmission-credentials.age;
        owner = "transmission";
        group = "transmission";
      };
    };
  };


  services.murmur = {
     enable = true;
     registerName = "wankbank";
     registerHostname = "murmur.samlockart.com";
     registerUrl = "murmur.samlockart.com";
     welcometext = "speak friend and enter...";
     bandwidth = 130000;
     allowHtml = false;
     autobanTime = 10;
     autobanAttempts = 60;
     sslKey = "${config.security.acme.certs."murmur.samlockart.com".directory}/key.pem";
     sslCert = "${config.security.acme.certs."murmur.samlockart.com".directory}/fullchain.pem";
   };

  security.acme.certs."murmur.samlockart.com" = {
    group = "murmur";
    postRun = "systemctl reload-or-restart murmur.service";
  };

  services.nginx.virtualHosts."murmur.samlockart.com".enableACME = true;

  services.botamusique = {
    enable = true;
    settings = {
      server = {
        host = config.services.murmur.registerHostname;
        port = config.services.murmur.port;
      };
      bot = {
        username = "cuckbot";
        comment = "Hi, I'm here to play music and have fun. Please treat me kindly.";
      };
    };
  };

  
  # manual host configuration
  networking.extraHosts =
    ''
      127.0.0.2 sync.samlockart.com
    '';


  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}

