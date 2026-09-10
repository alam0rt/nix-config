# Body of portable-secrets-decrypt; ./secrets.nix supplies the shebang,
# `set -euo pipefail` and PATH.
#
# Run either from a terminal (via `portable-unlock`, where the plugin can ask
# for a PIN) or headless as portable-secrets.service, which is what the
# automount on /run/portable-secrets triggers. Both are idempotent: whatever
# is already decrypted is left alone.
#
# Every secret is one file, decrypted under its own name in one pass, so the
# whole set costs a single touch. What each name means is a convention read
# elsewhere - see ./secrets/README.md.

secrets_dir=/etc/portable/secrets
plain_dir=/run/portable-secrets.d

if [ "$(id -u)" -ne 0 ]; then
  echo "portable-secrets-decrypt: must run as root" >&2
  exit 1
fi

shopt -s nullglob
encrypted=("$secrets_dir"/*.age)
if [ ${#encrypted[@]} -eq 0 ]; then
  echo "portable-secrets-decrypt: this image was built without secrets"
  exit 0
fi

install -d -m 0700 "$plain_dir"

pending=()
for f in "${encrypted[@]}"; do
  [ -e "$plain_dir/$(basename "$f" .age)" ] || pending+=("$f")
done

if [ ${#pending[@]} -eq 0 ]; then
  echo "portable-secrets-decrypt: already unlocked"
  exit 0
fi

# Headless, the plugin's "touch me" only reaches the journal, so say it
# somewhere the person in front of the machine will see it.
if [ ! -t 1 ]; then
  wall -n "Something wants the portable stick's secrets. Touch your YubiKey." || true
fi

for f in "${pending[@]}"; do
  name=$(basename "$f" .age)
  echo "portable-secrets-decrypt: decrypting $name - touch your YubiKey"
  (
    umask 077
    age -d -j fido2-hmac -o "$plain_dir/$name" "$f"
  )
done

echo "portable-secrets-decrypt: unlocked"
