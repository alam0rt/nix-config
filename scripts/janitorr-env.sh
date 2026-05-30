#!/usr/bin/env bash
#
# Run on sauron as root. Emits janitorr's API keys + Jellyfin creds on stdout.
# Prerequisites:
#   - Jellyfin API key named "janitorr" (Dashboard -> API Keys -> +)
#   - A Jellyfin user named "janitorr" with delete permissions
#
# Typical invocation from your laptop:
#   scp scripts/janitorr-env.sh sauron:/tmp/
#   ssh -t sauron sudo bash /tmp/janitorr-env.sh

set -euo pipefail

SONARR=$(grep -oP '(?<=<ApiKey>)[^<]+' /srv/data/sonarr/config.xml)
RADARR=$(grep -oP '(?<=<ApiKey>)[^<]+' /srv/data/radarr/config.xml)
JELLYSEERR=$(jq -r '.main.apiKey' /var/lib/jellyseerr/config/settings.json)
JELLYFIN=$(sqlite3 /srv/data/jellyfin/data/jellyfin.db \
  "SELECT AccessToken FROM ApiKeys WHERE Name='janitorr' LIMIT 1;")

if [[ -z "$JELLYFIN" ]]; then
  echo "error: no Jellyfin API key named 'janitorr' found." >&2
  echo "Create one in Jellyfin -> Dashboard -> API Keys, then re-run." >&2
  exit 1
fi

# Jellyfin requires user creds for deletes (API key alone is insufficient).
# Supply via env when piping into the agenix editor, e.g.:
#   JELLYFIN_USER=janitorr JELLYFIN_PASS='...' sudo -E bash /tmp/janitorr-env.sh
: "${JELLYFIN_USER:=janitorr}"
: "${JELLYFIN_PASS:=}"

cat <<EOF
CLIENTS_SONARR_APIKEY=$SONARR
CLIENTS_RADARR_APIKEY=$RADARR
CLIENTS_JELLYFIN_APIKEY=$JELLYFIN
CLIENTS_JELLYFIN_USERNAME=$JELLYFIN_USER
CLIENTS_JELLYFIN_PASSWORD=$JELLYFIN_PASS
CLIENTS_JELLYSEERR_APIKEY=$JELLYSEERR
EOF
