# Wifi, declared here, with the PSKs encrypted.
#
# NetworkManager's ensureProfiles writes these profiles into
# /run/NetworkManager/system-connections at boot, running each through
# envsubst with the environment file below - so the SSIDs live in the nix
# config in the clear, where they belong, and the pre-shared keys only ever
# exist as $WIFI_PSK_* pulled out of a YubiKey-encrypted file at runtime.
# Nothing about a PSK reaches the store.
#
# The environment file lives on the automount, so bringing wifi up is one of
# the things that asks for the key. If it never comes, this service fails on
# its own and NetworkManager still runs - type the password into nmtui like
# anyone else.
#
# Adding a network: add it here, then re-pack the environment file (which
# reads the PSKs out of this laptop's own NetworkManager profiles):
#
#   sudo scripts/portable-wifi-psks.sh | scripts/portable-secret.sh nm-env
#
# The variable name is the profile id uppercased with everything that isn't
# alphanumeric turned into _, prefixed WIFI_PSK_. The pack script derives it
# the same way, so the two cannot drift as long as the ids match.
{lib, ...}: let
  # Without the PSK file there is nothing to substitute: the profiles would be
  # written with empty passwords and the ensure-profiles unit would fail on a
  # missing EnvironmentFile. Better to ship no declarative wifi at all and use
  # nmtui, until `sudo scripts/portable-wifi-psks.sh | scripts/portable-secret.sh
  # nm-env` has been run.
  havePSKs = builtins.pathExists ./secrets/nm-env.age;

  # id -> ssid. They happen to be equal for all of these, but NetworkManager
  # treats them as different things and so should we.
  networks = {
    "wifi of sorrows 5ghz" = "wifi of sorrows 5ghz";
    "HG659-66FE" = "HG659-66FE";
    "HG659-66FE-5G" = "HG659-66FE-5G";
    "Telstra438C79" = "Telstra438C79";
  };

  # Mirrors `tr -c '[:alnum:]' '_'` in scripts/portable-wifi-psks.sh.
  envVar = id:
    "WIFI_PSK_"
    + lib.stringAsChars
    (c:
      if builtins.match "[A-Za-z0-9]" c != null
      then c
      else "_")
    (lib.toUpper id);

  profile = id: ssid: {
    connection = {
      inherit id;
      type = "wifi";
    };
    wifi = {
      mode = "infrastructure";
      inherit ssid;
    };
    wifi-security = {
      key-mgmt = "wpa-psk";
      psk = "$" + envVar id;
    };
    ipv4.method = "auto";
    ipv6 = {
      addr-gen-mode = "stable-privacy";
      method = "auto";
    };
  };
in {
  networking.networkmanager.ensureProfiles = lib.mkIf havePSKs {
    profiles = lib.mapAttrs profile networks;
    environmentFiles = ["/run/portable-secrets/nm-env"];
  };

  # Pull the mount in as an ordinary dependency rather than letting the
  # EnvironmentFile read trip the automount from inside systemd's own
  # plumbing: same YubiKey prompt, but ordered, and a missing key fails this
  # one unit instead of blocking somewhere awkward.
  systemd.services.NetworkManager-ensure-profiles.unitConfig.RequiresMountsFor =
    lib.mkIf havePSKs "/run/portable-secrets";
}
