# The networks this household knows, declared once.
#
# NetworkManager's ensureProfiles writes these into
# /run/NetworkManager/system-connections at boot, running each through
# envsubst against `networking.declarativeWifi.environmentFile`. So the SSIDs
# live here in the clear, where they belong, and the pre-shared keys only
# exist as $WIFI_PSK_* pulled out of an encrypted file at runtime - nothing
# about a PSK reaches the nix store.
#
# Where that file comes from is the host's business, and the two answers look
# very different:
#   - laptop, desktop: ./wifi-agenix.nix, rekeyed to the host key and
#     decrypted silently at activation. Boots exactly as before.
#   - portable: an automount that asks for a YubiKey, because a live stick has
#     no host key that isn't sitting on the same stick.
#
# Adding a network: add it below, then re-pack the PSKs and rekey:
#
#   sudo scripts/portable-wifi-psks.sh "wifi of sorrows 5ghz" \
#     | scripts/portable-secret.sh nm-env - nixos/config/network
#   nix run '.#agenix-rekey.x86_64-linux.rekey'
{
  config,
  lib,
  ...
}: let
  cfg = config.networking.declarativeWifi;

  # id -> ssid. Equal here, but NetworkManager treats them as different
  # things and so should we.
  networks = {
    "wifi of sorrows 5ghz" = "wifi of sorrows 5ghz";
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
  options.networking.declarativeWifi.environmentFile = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "/run/agenix/nm-env";
    description = ''
      File holding the pre-shared keys as `WIFI_PSK_<ID>=...` lines, one per
      profile id with everything non-alphanumeric turned into `_`.

      Null - the default - means no declarative wifi at all, which is the
      right answer when the file does not exist: the profiles would otherwise
      be written with empty passwords and NetworkManager-ensure-profiles would
      fail on a missing EnvironmentFile.
    '';
  };

  config = lib.mkIf (cfg.environmentFile != null) {
    networking.networkmanager.ensureProfiles = {
      profiles = lib.mapAttrs profile networks;
      environmentFiles = [cfg.environmentFile];
    };
  };
}
