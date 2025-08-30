{ config
, lib
, pkgs
, ... }:
let cfg = config.server;
in {
  services.minio = {
    enable = true;
  };
}
