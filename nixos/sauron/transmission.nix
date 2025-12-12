{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;
in {
  age.secrets.transmission-credentials = {
    file = ../../secrets/transmission-credentials.age;
    owner = "transmission";
    group = "transmission";
  };

  networking.firewall.allowedTCPPorts = [config.services.transmission.settings.peer-port];
  networking.firewall.allowedUDPPorts = [config.services.transmission.settings.peer-port];

  services.nginx.virtualHosts."transmission.middleearth.samlockart.com" = {
    forceSSL = false;
    enableACME = false;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.transmission.settings.rpc-port}";
    };
  };
  services.transmission = {
    enable = true;
    package = pkgs.transmission_4;
    openFirewall = false; # RPC accessed via nginx; peer-port opened explicitly above
    credentialsFile = config.age.secrets.transmission-credentials.path;
    settings = {
      home = "/srv/data/transmission";
      download-dir = "/srv/media/downloads";
      incomplete-dir = "/srv/media/downloads/.incomplete";
      trash-original-torrent-files = true;
      rpc-bind-address = "127.0.0.1"; # bind to localhost only
      rpc-port = 9091;
      umask = (builtins.fromTOML "octal = 0o0002").octal; # 0666 - 0002 = u+rw,g+rw,o+r
      rpc-whitelist = "127.0.0.1";
      rpc-whitelist-enabled = true;
      rpc-host-whitelist-enabled = false;
      ratio-limit = "0.0";
      ratio-limit-enabled = true;
      download-queue-size = 15;
      queue-stalled-minutes = 20;
      peer-port = 51413;
    };
  };

  # lazily get around auth ratelimiting caused by
  # sonarr/friends accessing the UI with incorrect user/pass
  systemd.timers."transmission-restart" = {
    wantedBy = ["timers.target"];
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
}
