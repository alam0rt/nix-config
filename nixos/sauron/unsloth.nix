{ config
, lib
, pkgs
, ... }:
let cfg = config.server;
in {
python3.14-unsloth
}