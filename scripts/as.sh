#!/usr/bin/env bash

set -euo pipefail

if [ -z "$1" ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

USERNAME="$1"

# shellcheck disable=SC2046
if ! { read -r AS_UID AS_GID <<< $(awk -F: -v user="$USERNAME" 'BEGIN {found=0} $1 == user {print $3, $4; found=1} END {if (!found) exit 1}' /etc/passwd); }; then
  echo "User '$USERNAME' not found in /etc/passwd."
  exit 1
fi

cd /

systemd-run --uid="$AS_UID" --gid="$AS_GID" --slice="user-$AS_UID.slice" --shell