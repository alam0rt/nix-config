{ config, ... }:
let
  domain = "pass.iced.cool";
in
{
  services.nginx.virtualHosts.${domain} = {
    # https://github.com/dani-garcia/vaultwarden/wiki/Deployment-examples#nixos-by-tklitschi
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.vaultwarden.config.ROCKET_PORT}";
      recommendedProxySettings = true;
    };
  };

  services.vaultwarden = {
    enable = true;
    backupDir = "/srv/data/vaultwarden";
    config = {
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      DOMAIN = "https://${domain}";
      SIGNUPS_ALLOWED = false; # sorry lads :^)
    };
  };
}
