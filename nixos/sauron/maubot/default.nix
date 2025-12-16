{
  config,
  lib,
  ...
}: let
  cfg = config.server;
in {
  age = {
    secrets = {
      maubot-secret-config = {
        rekeyFile = ./maubot-secret-config.age;
        owner = "maubot";
        group = "maubot";
      };
    };
  };
  services.nginx = let
    inherit (config.services.maubot) settings;
  in {
    virtualHosts."maubot.${cfg.domain}" = {
      forceSSL = true;
      useACMEHost = cfg.domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString settings.server.port}";
        proxyWebsockets = true;
      };
    };
  };
  # provide mbc cli
  environment.systemPackages = [config.services.maubot.package];

  services.maubot = {
    enable = true;
    dataDir = "/srv/data/maubot";
    extraConfigFile = config.age.secrets.maubot-secret-config.path;
    settings = {
      database = "sqlite:/srv/data/maubot/maubot.db";
    };
    plugins = with config.services.maubot.package.plugins; [chatgpt];
  };
}
