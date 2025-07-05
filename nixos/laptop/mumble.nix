{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.server;
in {
  services.murmur = {
    enable = true;
    registerName = "wankbank";
    welcometext = "speak friend and enter...";
    bandwidth = 130000;
    allowHtml = false;
    autobanTime = 10;
    openFirewall = true;
    autobanAttempts = 60;
  };

  # package overridden by ./pkgs/botamusique
  services.botamusique = {
    enable = true;
    settings = {
      server = {
        host = "127.0.0.1";
        port = config.services.murmur.port;
      };
      bot = {
        username = "cuckbot";
        comment = "Hi, I'm here to play music and have fun. Please treat me kindly.";
        database_path = "/var/lib/botamusique/bot.db";
        music_database_path = "/var/lib/botamusique/music.db";
      };
      debug = {
        ffmpeg = true;
        mumbleConnection = true;
      };
    };
  };
}
