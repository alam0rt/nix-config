# Feeds ./wifi.nix from agenix on the hosts that have a host key: the PSKs are
# rekeyed to it and decrypted at activation, so these machines boot and
# connect exactly as they did when the profiles were imperative. No YubiKey,
# no automount - that is only the portable stick's problem.
#
# Guarded on the source secret existing, so the hosts keep evaluating before
# it has been packed; until then wifi stays whatever NetworkManager already
# has on disk, which is what these hosts have always done.
#
# Once it exists, `agenix-rekey rekey` has to run before these hosts will
# evaluate again - the rekeyed path is resolved at eval time, so an undeclared
# or un-added rekeyed copy fails the config with "Path ... is not tracked by
# Git". That is agenix-rekey's normal bootstrap for any new secret in this
# repo, and it cannot be guarded away: rekey only writes copies of *declared*
# secrets, so a guard waiting for the rekeyed file is a guard that keeps the
# secret undeclared forever.
#
#   sudo scripts/portable-wifi-psks.sh "wifi of sorrows 5ghz" \
#     | scripts/portable-secret.sh nm-env - nixos/config/network
#   nix run '.#agenix-rekey.x86_64-linux.rekey'
#   git add nixos/config/network/nm-env.age nixos/config/secrets/rekeyed
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
