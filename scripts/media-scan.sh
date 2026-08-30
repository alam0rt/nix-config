#!/usr/bin/env bash
#
# Probe every media file under a root and emit one TSV row per file.
#
# Runs on sauron: ffprobe is there and the files are local. sauron has no
# python3 and no jq, so this stays pure shell + awk and the analysis happens
# on the laptop via media-report.py.
#
# Reads container/stream headers only — it does not decode, so a full pass
# over /srv/media is cheap and read-only.
#
# Usage:
#   scp scripts/media-scan.sh sauron:/tmp/
#   ssh sauron 'bash /tmp/media-scan.sh /srv/media' > media-scan.tsv
#   ./scripts/media-report.py media-scan.tsv
#
# Resume an interrupted scan by feeding back what you already have:
#   ssh sauron 'bash /tmp/media-scan.sh /srv/media /tmp/partial.tsv' >> partial.tsv
#
# Env: JOBS=8 parallel probes, EXTS=comma-separated extensions.
#
# Output columns (tab separated, path last so spaces in names are safe):
#   1 size_bytes   2 duration_s  3 total_bitrate  4 vcodec  5 width
#   6 height       7 vbitrate    8 abitrate       9 acodec  10 achannels
#   11 path

set -euo pipefail

# ---- worker mode: probe a single file, emit one row -------------------------
if [ "${1:-}" = "--probe" ]; then
    f=$2
    ffprobe -v error \
        -show_entries format=duration,size,bit_rate \
        -show_entries stream=codec_type,codec_name,width,height,bit_rate,channels \
        -of default=noprint_wrappers=0:nokey=0 \
        -- "$f" 2>/dev/null |
        awk -v path="$f" '
      BEGIN { FS = "="; abr = 0; vseen = 0; aseen = 0; acodec = "-"; ach = 0 }

      /^\[STREAM\]/  { ins = 1; ctype = cname = w = h = br = ch = ""; next }
      /^\[\/STREAM\]/ {
        if (ctype == "video" && !vseen) {
          vseen = 1; vcodec = cname; vw = w; vh = h; vbr = br
        } else if (ctype == "audio") {
          # Many mkv muxers omit per-stream bit_rate. Record codec+channels of
          # the first track so the report can estimate what it costs.
          if (br ~ /^[0-9]+$/) abr += br
          if (!aseen) { aseen = 1; acodec = cname; ach = ch + 0 }
        }
        ins = 0; next
      }
      /^\[FORMAT\]/   { inf = 1; next }
      /^\[\/FORMAT\]/ { inf = 0; next }

      {
        if (ins) {
          if      ($1 == "codec_type") ctype = $2
          else if ($1 == "codec_name") cname = $2
          else if ($1 == "width")      w     = $2
          else if ($1 == "height")     h     = $2
          else if ($1 == "channels")   ch    = $2
          else if ($1 == "bit_rate")   br    = $2
        } else if (inf) {
          if      ($1 == "duration")  dur = $2
          else if ($1 == "size")      sz  = $2
          else if ($1 == "bit_rate")  tbr = $2
        }
      }

      END {
        if (!vseen) exit 0                    # no video stream: not our business
        gsub(/[\t\n\r]/, " ", path)           # keep the TSV parseable
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%d\t%s\t%d\t%s\n",
          (sz     == "" ? "0"   : sz),
          (dur    == "" ? "0"   : dur),
          (tbr    == "" ? "N/A" : tbr),
          (vcodec == "" ? "?"   : vcodec),
          (vw     == "" ? "0"   : vw),
          (vh     == "" ? "0"   : vh),
          (vbr    == "" ? "N/A" : vbr),
          abr, acodec, ach, path
      }
    '
    exit 0
fi

# ---- driver ----------------------------------------------------------------
ROOT=${1:-/srv/media}
RESUME=${2:-}
JOBS=${JOBS:-8}
EXTS=${EXTS:-mkv,mp4,m4v,avi,ts,mov,wmv,mpg,mpeg,flv}

[ -d "$ROOT" ] || { echo "not a directory: $ROOT" >&2; exit 1; }

self=$(readlink -f "$0")
ext_re=$(printf '%s' "$EXTS" | tr ',' '|')

# Collect candidates first so we can report a total and skip finished work.
tmp=$(mktemp)
trap 'rm -f "$tmp" "$tmp.done"' EXIT

find "$ROOT" -type f -regextype posix-extended \
    -iregex ".*\.($ext_re)$" -print0 >"$tmp"

total=$(tr -dc '\0' <"$tmp" | wc -c)

if [ -n "$RESUME" ] && [ -s "$RESUME" ]; then
    cut -f11 "$RESUME" | sort -u >"$tmp.done"
    awk -v RS='\0' -v ORS='\0' -v done_list="$tmp.done" '
      BEGIN { while ((getline line < done_list) > 0) seen[line] = 1 }
      !($0 in seen)
    ' <"$tmp" >"$tmp.todo"
    mv "$tmp.todo" "$tmp"
    remaining=$(tr -dc '\0' <"$tmp" | wc -c)
    echo "found $total files, $remaining left to probe (${JOBS} parallel)" >&2
else
    echo "found $total files to probe (${JOBS} parallel)" >&2
fi

# ionice so a full sweep does not fight Jellyfin for the spindles.
xargs -0 -P "$JOBS" -I{} \
    ionice -c3 nice -n19 bash "$self" --probe {} <"$tmp"

echo "done" >&2
