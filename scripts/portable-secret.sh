#!/usr/bin/env bash

set -euo pipefail

# Encrypt something into the portable stick's secrets, to all three YubiKey
# master identities.
#
#   scripts/portable-secret.sh <name> [file]      # file, or stdin
#
# Names carry meaning to the stick (see nixos/portable/secrets/README.md):
#   nm-env              wifi PSKs, as WIFI_PSK_*=... lines
#   ssh-<filename>      installed to /home/sam/.ssh/<filename>
#   tailscale-authkey   used by services.tailscale.authKeyFile
# anything else is just decrypted under its own name for you to use by hand.
#
# Encryption is public-key only, so this needs no token; the stick needs one.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBKEY_DIR="$REPO_ROOT/nixos/config/secrets/pubkeys"
OUT_DIR="$REPO_ROOT/nixos/portable/secrets"

NAME="${1:-}"
SRC="${2:--}"

if [ -z "$NAME" ]; then
  echo "Usage: $0 <name> [file]   (reads stdin if no file)" >&2
  exit 1
fi

# The .pub files carry the age recipient in a comment above the plugin
# identity; only the recipient is needed to encrypt.
recipients=()
for pub in "$PUBKEY_DIR"/*.pub; do
  key="$(sed -n 's/^# public key: //p' "$pub" | head -n1)"
  if [ -z "$key" ]; then
    echo "$0: no recipient found in $pub" >&2
    exit 1
  fi
  recipients+=(-r "$key")
done

if [ ${#recipients[@]} -eq 0 ]; then
  echo "$0: no pubkeys in $PUBKEY_DIR" >&2
  exit 1
fi

out="$OUT_DIR/$NAME.age"
umask 077
if [ "$SRC" = "-" ]; then
  age -e "${recipients[@]}" -o "$out"
else
  age -e "${recipients[@]}" -o "$out" "$SRC"
fi

echo "wrote $out for $((${#recipients[@]} / 2)) YubiKeys" >&2
echo "git add it - a flake only sees tracked files - then rebuild the image" >&2
