# Body of portable-secrets-restore; ./secrets.nix supplies the shebang,
# `set -euo pipefail`, PATH, and $secrets / $user / $home.
#
# Reads through /run/portable-secrets, which is an automount: the first stat
# blocks until portable-secrets.service has decrypted everything, so simply
# looking for the files is what asks for the YubiKey.
#
# Only ssh keys need moving into place. Wifi is declarative (../wifi.nix
# hands NetworkManager the PSKs through the same automount) and tailscale
# reads its key straight off the mount.

if [ "$(id -u)" -ne 0 ]; then
  echo "portable-secrets-restore: must run as root" >&2
  exit 1
fi

shopt -s nullglob
keys=("$secrets"/ssh-*)

# The unit has RequiresMountsFor on $secrets, so a failed decrypt fails this
# before it runs: an empty glob here really does mean no ssh secrets.
if [ ${#keys[@]} -eq 0 ]; then
  echo "portable-secrets-restore: no ssh keys in this image"
  exit 0
fi

install -d -m 0700 -o "$user" -g "$user" "$home/.ssh"
for f in "${keys[@]}"; do
  name=$(basename "$f")
  install -m 0600 -o "$user" -g "$user" "$f" "$home/.ssh/${name#ssh-}"
done

echo "portable-secrets-restore: installed ${#keys[@]} ssh file(s) for sam"
