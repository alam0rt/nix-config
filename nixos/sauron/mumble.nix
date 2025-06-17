{
  config,
  lib,
  ...
}: let
  cfg = config.server;
in {
  services.murmur = {
    enable = true;
    registerName = "wankbank";
    registerHostname = "murmur.samlockart.com";
    registerUrl = "murmur.samlockart.com";
    welcometext = "speak friend and enter...";
    bandwidth = 130000;
    allowHtml = false;
    autobanTime = 10;
    openFirewall = true;
    autobanAttempts = 60;
    sslKey = "${config.security.acme.certs."murmur.samlockart.com".directory}/key.pem";
    sslCert = "${config.security.acme.certs."murmur.samlockart.com".directory}/fullchain.pem";
  };

  security.acme.certs."murmur.samlockart.com" = {
    group = "murmur";
    postRun = "systemctl reload-or-restart murmur.service";
  };

  services.nginx.virtualHosts."murmur.samlockart.com".enableACME = true;

  # required
  users.users.nginx.extraGroups = ["murmur"];

  # disabled while packge is broken
  services.botamusique = {
    enable = false;
#    package = foo;
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
}
