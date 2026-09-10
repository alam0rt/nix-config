# The stick's answer to "where does the PSK file come from": the YubiKey
# automount, because a live image has no host key that isn't sitting on the
# same stick. The networks themselves are shared with laptop and desktop in
# ../config/network/wifi.nix.
#
# The secret is the same file the fixed hosts rekey from - already encrypted
# to the three master identities - so ../secrets.nix ships it verbatim rather
# than keeping a second copy here.
{lib, ...}: let
  havePSKs = builtins.pathExists ../config/network/nm-env.age;
in {
  imports = [../config/network/wifi.nix];

  config = lib.mkIf havePSKs {
    networking.declarativeWifi.environmentFile = "/run/portable-secrets/nm-env";

    # Pull the mount in as an ordinary dependency rather than letting the
    # EnvironmentFile read trip the automount from inside systemd's own
    # plumbing: same YubiKey prompt, but ordered, and a missing key fails this
    # one unit instead of blocking somewhere awkward.
    systemd.services.NetworkManager-ensure-profiles.unitConfig.RequiresMountsFor = "/run/portable-secrets";
  };
}
