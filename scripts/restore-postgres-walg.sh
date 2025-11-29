#!/usr/bin/env bash

set -euo pipefail

# Simple WAL-G PostgreSQL Restore Script
# Usage: 
#   ./restore-postgres-walg.sh [DATABASE_NAME]           # List backups
#   ./restore-postgres-walg.sh -l [DATABASE_NAME]        # List backups with WAL-G
#   ./restore-postgres-walg.sh -v [DATABASE_NAME]        # Verify backup integrity
#   ./restore-postgres-walg.sh -d BACKUP_NAME DB_NAME    # Show backup details
# Example: ./restore-postgres-walg.sh synapse

MODE="list"
DATABASE_NAME=""
BACKUP_NAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--list)
            MODE="walg-list"
            shift
            ;;
        -v|--verify)
            MODE="verify"
            shift
            ;;
        -d|--details)
            MODE="details"
            BACKUP_NAME="$2"
            shift 2
            ;;
        *)
            DATABASE_NAME="$1"
            shift
            ;;
    esac
done

export SSH_USERNAME="hk1068"

DATABASE_NAME="${DATABASE_NAME:-synapse}"
REMOTE_HOST="hk-s020.rsync.net"
# requires full path like so
REMOTE_PATH="data1/home/${SSH_USERNAME}/postgres-backups/${DATABASE_NAME}"

# Set up WAL-G environment
export WALG_SSH_PREFIX="ssh://${SSH_USERNAME}@${REMOTE_HOST}/${REMOTE_PATH}"
export SSH_PRIVATE_KEY_PATH="${HOME}/.ssh/id_rsa"
export AWS_REGION="us-east-1"  # Required by WAL-G even for SSH

echo "Database: $DATABASE_NAME"
echo "Remote: ${SSH_USERNAME}@${REMOTE_HOST}:${REMOTE_PATH}"
echo ""

case $MODE in
    list)
        echo "=== Raw directory listing ==="
        ssh "${SSH_USERNAME}@${REMOTE_HOST}" "ls -alh ${REMOTE_PATH}"
        ;;
    
    walg-list)
        echo "=== WAL-G backup list ==="
        nix-shell -p wal-g --run "SSH_AUTH_SOCK=$SSH_AUTH_SOCK wal-g backup-list"
        ;;
    
    verify)
        echo "=== Verifying backups with WAL-G ==="
        echo ""
        echo "1. Listing all backups:"
        nix-shell -p wal-g --run "SSH_AUTH_SOCK=$SSH_AUTH_SOCK wal-g backup-list"
        echo ""
        echo "2. Checking WAL archive integrity:"
        nix-shell -p wal-g --run "SSH_AUTH_SOCK=$SSH_AUTH_SOCK wal-g wal-verify integrity"
        echo ""
        echo "3. Checking timeline integrity:"
        nix-shell -p wal-g --run "SSH_AUTH_SOCK=$SSH_AUTH_SOCK wal-g wal-verify timeline"
        ;;
    
    details)
        if [ -z "$BACKUP_NAME" ]; then
            echo "Error: Backup name required for details mode"
            echo "Usage: $0 -d BACKUP_NAME [DATABASE_NAME]"
            exit 1
        fi
        echo "=== Backup details for: $BACKUP_NAME ==="
        nix-shell -p wal-g jq --run "SSH_AUTH_SOCK=$SSH_AUTH_SOCK wal-g backup-list --detail --json | jq '.[] | select(.backup_name == \"$BACKUP_NAME\")'"
        ;;
esac
