#!/usr/bin/env bash

set -euo pipefail

# Pack a staging directory into the encrypted state bundle the portable stick
# unlocks at runtime (see nixos/portable/secrets/README.md).
#
#   scripts/portable-pack-state.sh ~/portable-state
#
# Encryption is to the three YubiKey master identities and is public-key only,
# so this needs no token; `sudo portable-unlock` on the stick does.
#
# The staging directory is expected to look like:
#   NetworkManager/system-connections/*.nmconnection
#   ssh/*
#   tailscale/authkey

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBKEY_DIR="$REPO_ROOT/nixos/config/secrets/pubkeys"

STAGE="${1:-}"
OUT="${2:-$REPO_ROOT/nixos/portable/secrets/state.tar.age}"

if [ -z "$STAGE" ] || [ ! -d "$STAGE" ]; then
  echo "Usage: $0 <staging-dir> [output.age]" >&2
  exit 1
fi

# The .pub files carry the age recipient in a comment line above the plugin
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

# Deterministic tar, so an unchanged bundle re-encrypts to the same plaintext
# and does not churn git and the store on every rebuild. (The age ciphertext
# still differs per run - age has no deterministic mode.)
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

tar -cf "$tmp/state.tar" \
  --sort=name \
  --owner=0 --group=0 --numeric-owner \
  --mtime=@0 \
  -C "$STAGE" .

age -e "${recipients[@]}" -o "$OUT" "$tmp/state.tar"

echo "wrote $OUT ($(du -h "$OUT" | cut -f1)) for ${#recipients[@]} YubiKeys"
echo "rebuild the image to pick it up: nix build .#portable-iso"
