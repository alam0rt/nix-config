#!/usr/bin/env bash

set -euo pipefail

# Dump this machine's wifi PSKs as the environment file the portable stick's
# declarative NetworkManager profiles expect. Needs root: the PSKs live in
# root-only files under /etc/NetworkManager/system-connections.
#
#   sudo scripts/portable-wifi-psks.sh | scripts/portable-secret.sh nm-env
#
# Piping straight into the encryptor keeps the plaintext off disk. The
# variable name matches envVar in nixos/portable/wifi.nix: the profile id,
# uppercased, with anything non-alphanumeric turned into _.

CONN_DIR=/etc/NetworkManager/system-connections

if [ "$(id -u)" -ne 0 ]; then
  echo "$0: must run as root" >&2
  exit 1
fi

shopt -s nullglob
found=0

for f in "$CONN_DIR"/*.nmconnection; do
  psk="$(sed -n 's/^psk=//p' "$f" | head -n1)"
  [ -n "$psk" ] || continue

  id="$(sed -n 's/^id=//p' "$f" | head -n1)"
  [ -n "$id" ] || id="$(basename "$f" .nmconnection)"

  var="WIFI_PSK_$(echo "$id" | tr '[:lower:]' '[:upper:]' | tr -c '[:alnum:]\n' '_')"
  echo "$var=$psk"
  found=$((found + 1))
done

if [ "$found" -eq 0 ]; then
  echo "$0: no PSKs found in $CONN_DIR" >&2
  exit 1
fi

echo "$0: dumped $found PSK(s)" >&2
