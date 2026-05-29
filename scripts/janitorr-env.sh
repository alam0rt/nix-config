#!/usr/bin/env bash
#
# Run on sauron as root. Emits janitorr's four API keys as env vars on stdout.
# Prerequisite: a Jellyfin API key named "janitorr" (Dashboard -> API Keys -> +).
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

cat <<EOF
CLIENTS_SONARR_APIKEY=$SONARR
CLIENTS_RADARR_APIKEY=$RADARR
CLIENTS_JELLYFIN_APIKEY=$JELLYFIN
CLIENTS_JELLYSEERR_APIKEY=$JELLYSEERR
EOF
