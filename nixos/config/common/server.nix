{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.server;
in {
  options.server = {
    domain = mkOption {
      type = types.str;
      default = "middleearth.samlockart.com";
      description = "The base domain for internal services (used with wildcard ACME cert)";
    };
  };
}
