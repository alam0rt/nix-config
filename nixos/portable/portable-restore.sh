# Body of portable-secrets-restore; ./secrets.nix supplies the shebang,
# `set -euo pipefail` and PATH.
#
# Reads through /run/portable-secrets, which is an automount: the first stat
# blocks until portable-secrets.service has decrypted the bundle, so simply
# looking for the files is what asks for the YubiKey.

state=/run/portable-secrets/state

if [ "$(id -u)" -ne 0 ]; then
  echo "portable-secrets-restore: must run as root" >&2
  exit 1
fi

if [ ! -d "$state" ]; then
  echo "portable-secrets-restore: no state bundle in this image"
  exit 0
fi

if compgen -G "$state/NetworkManager/system-connections/*" >/dev/null; then
  install -d -m 0700 /etc/NetworkManager/system-connections
  install -m 0600 "$state"/NetworkManager/system-connections/* \
    /etc/NetworkManager/system-connections/
  nmcli connection reload
  echo "portable-secrets-restore: wifi connections installed"
fi

if compgen -G "$state/ssh/*" >/dev/null; then
  install -d -m 0700 -o sam -g sam /home/sam/.ssh
  install -m 0600 -o sam -g sam "$state"/ssh/* /home/sam/.ssh/
  echo "portable-secrets-restore: ssh keys installed for sam"
fi

# tailscale needs no help here: services.tailscale.authKeyFile points into
# /run/portable-secrets, so tailscaled-autoconnect's own read is the trigger.
echo "portable-secrets-restore: done"
