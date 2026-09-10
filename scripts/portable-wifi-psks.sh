#!/usr/bin/env bash

set -euo pipefail

# Dump this machine's wifi PSKs as the environment file the portable stick's
# declarative NetworkManager profiles expect. Needs root: the PSKs live in
# root-only files under /etc/NetworkManager/system-connections.
#
#   sudo scripts/portable-wifi-psks.sh [id...] \
#     | scripts/portable-secret.sh nm-env - nixos/config/network
#
# With no arguments it dumps every network this machine knows; name the ids
# to dump only those, which is usually what you want - the declared list in
# nixos/config/network/wifi.nix is shorter than what a laptop accumulates.
#
# Piping straight into the encryptor keeps the plaintext off disk. The
# variable name matches envVar in nixos/config/network/wifi.nix: the profile
# id, uppercased, with anything non-alphanumeric turned into _.

CONN_DIR=/etc/NetworkManager/system-connections

if [ "$(id -u)" -ne 0 ]; then
  echo "$0: must run as root" >&2
  exit 1
fi

shopt -s nullglob
found=0
wanted=("$@")
declare -A seen=()

for f in "$CONN_DIR"/*.nmconnection; do
  id="$(sed -n 's/^id=//p' "$f" | head -n1)"
  [ -n "$id" ] || id="$(basename "$f" .nmconnection)"

  psk="$(sed -n 's/^psk=//p' "$f" | head -n1)"
  if [ -z "$psk" ]; then
    # psk-flags=1 keeps the key in the user's keyring instead of the file.
    # Skipping quietly would pack a profile with an empty password, which
    # only shows up as a stick that will not join the network.
    if grep -q '^\[wifi-security\]' "$f"; then
      echo "$0: $id has no psk in the file (agent-owned?); not packed" >&2
    fi
    continue
  fi

  if [ ${#wanted[@]} -gt 0 ]; then
    match=0
    for w in "${wanted[@]}"; do
      [ "$w" = "$id" ] && match=1
    done
    [ "$match" -eq 1 ] || continue
  fi

  var="WIFI_PSK_$(echo "$id" | tr '[:lower:]' '[:upper:]' | tr -c '[:alnum:]\n' '_')"

  # Punctuation all collapses to _, so two ids can land on one variable and
  # the last assignment silently wins in systemd's parser - pairing an SSID
  # with someone else's key.
  if [ -n "${seen[$var]:-}" ]; then
    echo "$0: $id and ${seen[$var]} both map to $var - name one id explicitly" >&2
    exit 1
  fi
  seen[$var]="$id"

  echo "$var=$psk"
  found=$((found + 1))
done

if [ "$found" -eq 0 ]; then
  echo "$0: no PSKs found in $CONN_DIR${wanted[*]:+ for: ${wanted[*]}}" >&2
  exit 1
fi

echo "$0: dumped $found PSK(s)" >&2
