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
    registerHostname = "foobur.samlockart.com";
    registerUrl = "foobur.samlockart.com";
    welcometext = "speak friend and enter...";
    bandwidth = 130000;
    allowHtml = false;
    autobanTime = 10;
    openFirewall = true;
    autobanAttempts = 60;
  };

  # disabled while packge is broken
  services.botamusique = {
    enable = true;
    package = pkg.propagandabot;
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
