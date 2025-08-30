{ config
, lib
, pkgs
, ... }:
let cfg = config.server;
in {
  services.minio = {
    enable = true;
    listenAddress = "127.0.0.1:9999";
    consoleAddress = "127.0.0.1:9001";
    rootCredentialsFile = "/srv/data/minio/creds.env";
    dataDir = "/srv/data/minio/data";
    configDir = "/srv/data/minio/config";
    certificatesDir = "/srv/data/minio/certs";
  };
  services.nginx.virtualHosts."s3.iced.cool" = {
    forceSSL = false;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://${config.services.minio.listenAddress}";
    };
  };

  services.nginx.virtualHosts."s3console.iced.cool" = {
    forceSSL = false;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://${config.services.minio.consoleAddress}";
    };
  };
}
