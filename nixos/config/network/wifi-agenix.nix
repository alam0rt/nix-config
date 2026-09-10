# Feeds ./wifi.nix from agenix on the hosts that have a host key: the PSKs are
# rekeyed to it and decrypted at activation, so these machines boot and
# connect exactly as they did when the profiles were imperative. No YubiKey,
# no automount - that is only the portable stick's problem.
#
# Guarded on the source secret existing so the fixed hosts keep evaluating
# before it has been packed. Until then, wifi stays whatever NetworkManager
# already has on disk.
{
  config,
  lib,
  ...
}: let
  source = ./nm-env.age;
  havePSKs = builtins.pathExists source;
in {
  imports = [./wifi.nix];

  config = lib.mkIf havePSKs {
    age.secrets.nm-env.rekeyFile = source;
    networking.declarativeWifi.environmentFile = config.age.secrets.nm-env.path;
  };
}
