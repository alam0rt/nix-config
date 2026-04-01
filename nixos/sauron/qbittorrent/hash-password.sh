#!/usr/bin/env bash
set -euo pipefail

read -rsp "Password: " password
echo

nix shell nixpkgs#python3 --command python3 - "$password" <<'EOF'
import sys, hashlib, os, base64

password = sys.argv[1]
salt = os.urandom(16)
key = hashlib.pbkdf2_hmac('sha1', password.encode('utf-8'), salt, 100000, 64)
print(f"@ByteArray({base64.b64encode(salt).decode()}:{base64.b64encode(key).decode()})")
EOF
