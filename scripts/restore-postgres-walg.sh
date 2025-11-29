#!/usr/bin/env bash

set -euo pipefail

# WAL-G wrapper with environment configured for rsync.net backups
# Usage: ./restore-postgres-walg.sh [DATABASE_NAME] [WAL-G ARGS...]
# Examples:
#   ./restore-postgres-walg.sh synapse backup-list
#   ./restore-postgres-walg.sh synapse wal-verify integrity
#   ./restore-postgres-walg.sh synapse backup-fetch /path/to/restore LATEST

DATABASE_NAME="${1:-synapse}"
shift || true

export SSH_USERNAME="hk1068"
REMOTE_HOST="hk-s020.rsync.net"
REMOTE_PATH="data1/home/${SSH_USERNAME}/postgres-backups/${DATABASE_NAME}"

# Set up WAL-G environment
export WALG_SSH_PREFIX="ssh://${SSH_USERNAME}@${REMOTE_HOST}/${REMOTE_PATH}"
export SSH_PRIVATE_KEY_PATH="${HOME}/.ssh/id_rsa"
export AWS_REGION="us-east-1"  # Required by WAL-G even for SSH

echo "Database: $DATABASE_NAME"
echo "WALG_SSH_PREFIX: $WALG_SSH_PREFIX"
echo ""

# Run wal-g with all remaining arguments
nix-shell -p wal-g --run "SSH_AUTH_SOCK=$SSH_AUTH_SOCK wal-g $*"
