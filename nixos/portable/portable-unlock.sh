# Body of the `portable-unlock` command; wrapped by ./secrets.nix, which
# supplies the shebang, `set -euo pipefail`, PATH and PORTABLE_TS_FLAGS.
#
# Every *.age file baked into the image is encrypted to the three YubiKey
# master identities, so the image itself gives nothing away. Decryption needs
# a key present and touched, and the plaintext only ever lands on tmpfs.

secrets_dir=/etc/portable/secrets
run_dir=/run/portable-secrets
state_dir=/run/portable-state

if [ "$(id -u)" -ne 0 ]; then
  echo "portable-unlock: must run as root (try: sudo portable-unlock)" >&2
  exit 1
fi

shopt -s nullglob
encrypted=("$secrets_dir"/*.age)
if [ ${#encrypted[@]} -eq 0 ]; then
  echo "portable-unlock: no secrets in $secrets_dir - the ISO was built without any" >&2
  exit 1
fi

install -d -m 0700 "$run_dir"

for f in "${encrypted[@]}"; do
  name=$(basename "$f" .age)
  out="$run_dir/$name"
  if [ -e "$out" ]; then
    echo "portable-unlock: $name already unlocked"
    continue
  fi
  echo "portable-unlock: decrypting $name - touch your YubiKey"
  (
    umask 077
    age -d -j fido2-hmac -o "$out" "$f"
  )
done

# state.tar is the bundle the pack script builds; anything else is left in
# $run_dir for you to use by hand.
if [ ! -f "$run_dir/state.tar" ]; then
  echo "portable-unlock: unlocked into $run_dir"
  exit 0
fi

rm -rf "$state_dir"
install -d -m 0700 "$state_dir"
tar -xf "$run_dir/state.tar" -C "$state_dir"

if compgen -G "$state_dir/NetworkManager/system-connections/*" >/dev/null; then
  install -d -m 0700 /etc/NetworkManager/system-connections
  install -m 0600 "$state_dir"/NetworkManager/system-connections/* \
    /etc/NetworkManager/system-connections/
  nmcli connection reload
  echo "portable-unlock: wifi connections installed"
fi

if compgen -G "$state_dir/ssh/*" >/dev/null; then
  install -d -m 0700 -o sam -g sam /home/sam/.ssh
  install -m 0600 -o sam -g sam "$state_dir"/ssh/* /home/sam/.ssh/
  echo "portable-unlock: ssh keys installed for sam"
fi

if [ -f "$state_dir/tailscale/authkey" ]; then
  read -r -a ts_flags <<<"$PORTABLE_TS_FLAGS"
  if tailscale up --auth-key "$(cat "$state_dir/tailscale/authkey")" "${ts_flags[@]}"; then
    echo "portable-unlock: tailscale up"
  else
    echo "portable-unlock: tailscale up failed - key may be used or expired" >&2
  fi
fi

echo "portable-unlock: done; plaintext lives in $run_dir and $state_dir (tmpfs)"
