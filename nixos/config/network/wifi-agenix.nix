# Feeds ./wifi.nix from agenix on the hosts that have a host key: the PSKs are
# rekeyed to it and decrypted at activation, so these machines boot and
# connect exactly as they did when the profiles were imperative. No YubiKey,
# no automount - that is only the portable stick's problem.
#
# Guarded twice, because either half missing breaks a machine you rely on:
#
#   - the source secret, so the hosts keep evaluating before it is packed
#   - this host's rekeyed directory, because agenix-rekey resolves the rekeyed
#     path at eval time. Declaring the secret before `agenix-rekey rekey` has
#     run (and the result is git-added, which is what makes it visible to the
#     flake) fails the whole config with "Path ... is not tracked by Git" -
#     no wifi, no rebuild, on a laptop that was working a minute ago.
#
# So this turns itself on only once both halves are in the repo. Until then
# wifi stays whatever NetworkManager already has on disk, which is what these
# hosts have always done.
{
  config,
  lib,
  ...
}: let
  source = ./nm-env.age;
  rekeyed = ../secrets/rekeyed + "/${config.networking.hostName}";
  havePSKs = builtins.pathExists source && builtins.pathExists rekeyed;
in {
  imports = [./wifi.nix];

  config = lib.mkIf havePSKs {
    age.secrets.nm-env.rekeyFile = source;
    networking.declarativeWifi.environmentFile = config.age.secrets.nm-env.path;
  };
}
