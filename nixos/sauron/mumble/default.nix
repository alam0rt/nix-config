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
    tls.keyPath = "${config.security.acme.certs."murmur.samlockart.com".directory}/key.pem";
    tls.certPath = "${config.security.acme.certs."murmur.samlockart.com".directory}/fullchain.pem";
  };

  security.acme.certs."murmur.samlockart.com" = {
    group = "murmur";
    postRun = "systemctl reload-or-restart murmur.service";
  };

  services.nginx.virtualHosts."murmur.samlockart.com".enableACME = true;

  # required
  users.users.nginx.extraGroups = ["murmur"];

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
        # Relative paths that don't exist yet resolve against the package
        # directory in the read-only store, so pin them to the state dir.
        # These are the names upstream defaults to.
        database_path = "/var/lib/botamusique/settings-cuckbot.db";
        music_database_path = "/var/lib/botamusique/music.db";
        music_folder = "/var/lib/botamusique/music_folder/";
      };
    };
  };

  # yt-dlp shells out to deno to solve YouTube's JS challenges, and V8's JIT
  # needs writable+executable memory.
  systemd.services.botamusique.serviceConfig.MemoryDenyWriteExecute = lib.mkForce false;
}
