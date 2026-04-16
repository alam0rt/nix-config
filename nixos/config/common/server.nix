{
  config,
  lib,
  ...
}: let
  cfg = config.server;
in {
  options.server = {
    domain = lib.mkOption {
      type = lib.types.str;
      default = "middleearth.samlockart.com";
      description = "The base domain for internal services (used with wildcard ACME cert)";
    };
  };
}
