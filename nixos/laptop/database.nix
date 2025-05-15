{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = { };
in
{
  # ...
  config.services.patroni = {
    enable = true;
    name = "foo-1";
    scope = "foo";
    otherNodeIps = [ "100.64.0.24" ];
  };
}
