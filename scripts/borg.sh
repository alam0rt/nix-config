#!/usr/bin/env bash

set -euo pipefail

# Borg wrapper with environment configured for rsync.net backups
# Usage: ./borg.sh [REPO_NAME] [BORG ARGS...]
# Examples:
#   ./borg.sh mordor/vault list
#   ./borg.sh mordor/vault info
#   ./borg.sh mordor/srv/data list --last 5
#   ./borg.sh mordor/vault extract ::archive-name path/to/restore

REPO_NAME="${1:-mordor/vault}"
shift || true

export SSH_USERNAME="hk1068"
REMOTE_HOST="${SSH_USERNAME}.rsync.net"
BORG_REPO="${SSH_USERNAME}@${REMOTE_HOST}:${REPO_NAME}"

# Repository root directory
REPO_ROOT="$(git rev-parse --show-toplevel)"

BORG_SECRET_PATH="${REPO_ROOT}/secrets/borg.age"

# Set up Borg environment
export BORG_REPO
export BORG_RSH="ssh -i ${HOME}/.ssh/id_rsa"
export BORG_RELOCATED_REPO_ACCESS_IS_OK="1"
export BORG_REMOTE_PATH="borg14"

get_secret() {
    local -r secret_path="$1"
    local -r secret_dir="$(dirname "${secret_path}")"
    local -r secret_file="$(basename "${secret_path}")"

    if command -v agenix &> /dev/null && [ -f "${BORG_SECRET_PATH}" ]; then
        cd "${secret_dir}"
        agenix -d "${secret_file}"
    else
        echo "Error: agenix not found or secrets file missing" >&2
        exit 1
    fi
}

export BORG_PASSPHRASE="$(get_secret "${BORG_SECRET_PATH}")"

nix-shell -p borgbackup --run "SSH_AUTH_SOCK=$SSH_AUTH_SOCK borg $*"
