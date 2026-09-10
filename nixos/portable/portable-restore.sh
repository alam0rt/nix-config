# Body of portable-secrets-restore; ./secrets.nix supplies the shebang,
# `set -euo pipefail` and PATH.
#
# Reads through /run/portable-secrets, which is an automount: the first stat
# blocks until portable-secrets.service has decrypted everything, so simply
# looking for the files is what asks for the YubiKey.
#
# Only ssh keys need moving into place. Wifi is declarative (../wifi.nix
# hands NetworkManager the PSKs through the same automount) and tailscale
# reads its key straight off the mount.

secrets=/run/portable-secrets

if [ "$(id -u)" -ne 0 ]; then
  echo "portable-secrets-restore: must run as root" >&2
  exit 1
fi

shopt -s nullglob
keys=("$secrets"/ssh-*)

if [ ${#keys[@]} -eq 0 ]; then
  echo "portable-secrets-restore: no ssh keys in this image"
  exit 0
fi

install -d -m 0700 -o sam -g sam /home/sam/.ssh
for f in "${keys[@]}"; do
  name=$(basename "$f")
  install -m 0600 -o sam -g sam "$f" "/home/sam/.ssh/${name#ssh-}"
done

echo "portable-secrets-restore: installed ${#keys[@]} ssh file(s) for sam"
