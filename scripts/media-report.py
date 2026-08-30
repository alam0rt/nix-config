#!/usr/bin/env python3
"""Judge re-encode savings from a media-scan.sh TSV.

Every file is compared against a target video bitrate for its resolution. The
targets default to what the pool already demonstrates is watchable -- Endeavour
runs 1080p HEVC at 3.2 Mbps, South Park at 1.6 -- with headroom on top.

    ./scripts/media-report.py media-scan.tsv
    ./scripts/media-report.py media-scan.tsv --target 1080=3500 --min-saving 2
    ./scripts/media-report.py media-scan.tsv --csv candidates.csv

The saving figures are ESTIMATES. They assume the target bitrate is actually
acceptable for the content, which is true for clean digital sources and least
true for grainy film scans. Encode a handful and compare before trusting the
totals.
"""

import argparse
import csv
import os
import sys
from collections import defaultdict

# Video bitrate (kbps) we think each resolution class needs in HEVC.
DEFAULT_TARGETS = {2160: 10000, 1080: 4000, 720: 2500, 480: 1200, 360: 800}

# Resolution class is chosen by WIDTH, not height: a 2.39:1 scope film stored at
# 1920x800 is 1080p content that happens to be letterboxed, and tiering it on
# height would demand a 720p bitrate of it. 1,686 files on this pool are shaped
# that way, so the distinction is worth 5 TB of misjudged savings.
WIDTH_TIERS = [(3840, 2160), (1900, 1080), (1200, 720), (700, 480), (0, 360)]

# Codecs that are already modern; only worth touching if wildly over target.
EFFICIENT = {"hevc", "h265", "av1", "vp9"}

# How far above target an already-efficient file must sit to be worth redoing.
EFFICIENT_SLACK = 1.4

# Most mkv muxers omit per-stream audio bitrate, so it has to be estimated from
# codec and channel count. Audio is passed through untouched by the re-encode,
# so this is subtracted from the current video bitrate AND added back to the
# projected size -- getting it wrong inflates the savings in both directions.
# Per-channel rates, so 5.1 and stereo tracks in the same codec are costed
# differently: 6ch aac lands near 384k, 6ch eac3 near 640k, 6ch dts near 1.5M.
AUDIO_BPS_PER_CH = {"truehd": 500e3, "dts": 256e3, "flac": 170e3,
                    "eac3": 110e3, "ac3": 75e3, "mp3": 96e3,
                    "aac": 64e3, "vorbis": 64e3, "opus": 48e3}


def estimate_audio(codec, channels):
    ch = channels if channels > 0 else 2
    return AUDIO_BPS_PER_CH.get(codec.lower(), 64e3) * ch

GiB = 1024**3
TiB = 1024**4


def tier(width, targets):
    """Target bitrate for a file, chosen by frame width."""
    for min_w, klass in WIDTH_TIERS:
        if width >= min_w:
            return targets.get(klass, targets[min(targets)]), klass
    return targets[min(targets)], min(targets)


def human(n):
    if abs(n) >= TiB:
        return f"{n / TiB:.2f} TB"
    return f"{n / GiB:.0f} GB"


def group_of(path, root="/srv/media"):
    """Series name for TV, film folder for movies -- what you queue as a unit."""
    rel = path[len(root):].lstrip("/") if path.startswith(root) else path.lstrip("/")
    parts = rel.split("/")
    if len(parts) >= 2:
        return f"{parts[0]}/{parts[1]}"
    return parts[0] if parts else "?"


def load(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line:
                continue
            f = line.split("\t")
            if len(f) != 11:
                print(f"skipping malformed line {lineno}", file=sys.stderr)
                continue
            size, dur, tbr, vcodec, w, h, vbr, abr, acodec, ach, fpath = f

            def num(x, default=0.0):
                try:
                    return float(x)
                except ValueError:
                    return default

            size, dur = num(size), num(dur)
            if size <= 0 or dur <= 0:
                continue

            abr = num(abr)
            audio_estimated = abr <= 0
            if audio_estimated:
                abr = estimate_audio(acodec, int(num(ach)))

            vbr_v = num(vbr, -1)
            if vbr_v <= 0:
                # ffprobe leaves per-stream bitrate N/A on most mkv. Derive it:
                # total payload minus what the audio tracks account for.
                vbr_v = max((size * 8 / dur) - abr, 0)

            rows.append({
                "size": size, "dur": dur, "vcodec": vcodec.lower(),
                "width": int(num(w)), "height": int(num(h)),
                "vbr": vbr_v, "abr": abr,
                "acodec": acodec, "audio_est": audio_estimated,
                "path": fpath, "group": group_of(fpath),
            })
    return rows


def classify(r, targets, min_saving_gib, skip_codecs=()):
    kbps, klass = tier(r["width"], targets)
    target_bps = kbps * 1000
    r["target"], r["class"] = target_bps, klass

    if r["vcodec"] in skip_codecs:
        r["verdict"], r["saving"] = f"{r['vcodec']} left alone", 0.0
    elif r["vcodec"] in EFFICIENT and r["vbr"] <= target_bps * EFFICIENT_SLACK:
        r["verdict"], r["saving"] = "already efficient", 0.0
    elif r["vbr"] <= target_bps:
        r["verdict"], r["saving"] = "at or under target", 0.0
    else:
        new_size = (target_bps + r["abr"]) * r["dur"] / 8
        saving = max(r["size"] - new_size, 0.0)
        if saving < min_saving_gib * GiB:
            r["verdict"], r["saving"] = "below threshold", 0.0
        else:
            r["verdict"], r["saving"] = "candidate", saving
    return r


def bar(frac, width=22):
    filled = int(round(frac * width))
    return "#" * filled + "." * (width - filled)


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("tsv", help="output of media-scan.sh")
    p.add_argument("--target", action="append", default=[], metavar="H=KBPS",
                   help="override a resolution tier, e.g. 1080=3500 (repeatable)")
    p.add_argument("--min-saving", type=float, default=0.5, metavar="GB",
                   help="ignore files saving less than this (default 0.5)")
    p.add_argument("--top", type=int, default=25, help="rows per table (default 25)")
    p.add_argument("--pool-free", type=float, default=None, metavar="TB",
                   help="current free space, to project the post-encode figure")
    p.add_argument("--pool-size", type=float, default=None, metavar="TB",
                   help="pool capacity, used with --pool-free")
    p.add_argument("--csv", metavar="FILE", help="write per-file candidates here")
    p.add_argument("--exclude", action="append", default=[], metavar="SUBSTR",
                   help="drop paths containing this, e.g. /downloads/ (repeatable)")
    p.add_argument("--skip-codec", metavar="LIST",
                   help="never touch these codecs whatever their bitrate, e.g. "
                        "hevc,av1 -- the conservative policy, since a high-bitrate "
                        "modern encode is usually a deliberate quality choice")
    args = p.parse_args()

    targets = dict(DEFAULT_TARGETS)
    for spec in args.target:
        try:
            h, kbps = spec.split("=")
            targets[int(h)] = int(kbps)
        except ValueError:
            p.error(f"bad --target {spec!r}, expected H=KBPS")

    rows = load(args.tsv)
    if args.exclude:
        before = len(rows)
        rows = [r for r in rows
                if not any(x in r["path"] for x in args.exclude)]
        print(f"excluded {before - len(rows):,} files by path", file=sys.stderr)
    skip = {c.strip().lower() for c in args.skip_codec.split(",")} \
        if args.skip_codec else set()
    rows = [classify(r, targets, args.min_saving, skip) for r in rows]
    if not rows:
        print("no usable rows", file=sys.stderr)
        return 1

    total_size = sum(r["size"] for r in rows)
    total_saving = sum(r["saving"] for r in rows)
    cands = [r for r in rows if r["verdict"] == "candidate"]

    w = 78
    print("=" * w)
    print("RE-ENCODE SAVINGS ESTIMATE".center(w))
    print("=" * w)
    print(f"  targets   " + "  ".join(f"{h}p:{kb / 1000:g}M"
                                      for h, kb in sorted(targets.items(), reverse=True)
                                      if h) + f"  (+ audio kept as-is)")
    print(f"  scanned   {len(rows):,} files, {human(total_size)}")
    print(f"  candidate {len(cands):,} files, {human(sum(r['size'] for r in cands))}")
    print(f"  saving    {human(total_saving)}"
          f"  ({total_saving / total_size * 100:.1f}% of everything scanned)")
    if args.pool_free is not None:
        free = args.pool_free * TiB + total_saving
        line = f"  pool      {human(args.pool_free * TiB)} free -> {human(free)} free"
        if args.pool_size:
            used_pct = (args.pool_size * TiB - free) / (args.pool_size * TiB) * 100
            line += f"  ({used_pct:.0f}% used)"
        print(line)

    # ---- where it comes from ----
    print("\n" + "-" * w)
    print("BY TREE")
    print("-" * w)
    trees = defaultdict(lambda: [0, 0.0, 0.0])
    for r in rows:
        t = trees[r["group"].split("/")[0]]
        t[0] += r["verdict"] == "candidate"
        t[1] += r["size"]
        t[2] += r["saving"]
    print(f"  {'tree':<26} {'size':>9} {'saving':>9} {'files':>7}")
    for name, (n, size, saving) in sorted(trees.items(), key=lambda kv: -kv[1][2]):
        print(f"  {name:<26} {human(size):>9} {human(saving):>9} {n:>7,}")

    # ---- worst offenders ----
    print("\n" + "-" * w)
    print(f"TOP {args.top} BY SAVING")
    print("-" * w)
    groups = defaultdict(lambda: [0, 0.0, 0.0, [], []])
    for r in rows:
        g = groups[r["group"]]
        g[0] += r["verdict"] == "candidate"
        g[1] += r["size"]
        g[2] += r["saving"]
        if r["verdict"] == "candidate":
            g[3].append(r["vbr"])
            g[4].append(r["vcodec"])
    ranked = sorted(groups.items(), key=lambda kv: -kv[1][2])[: args.top]
    if ranked:
        peak = ranked[0][1][2] or 1
        print(f"  {'title':<40} {'now':>7} {'save':>8} {'Mbps':>6}  codec")
        for name, (n, size, saving, brs, cs) in ranked:
            if saving <= 0:
                continue
            mbps = sum(brs) / len(brs) / 1e6 if brs else 0
            codec = max(set(cs), key=cs.count) if cs else "-"
            label = name if len(name) <= 40 else name[:37] + "..."
            print(f"  {label:<40} {human(size):>7} {human(saving):>8} "
                  f"{mbps:>6.1f}  {codec}")
        print(f"\n  {'':<40} {bar(1.0)}  = {human(peak)}")

    # ---- what we are leaving alone, and why ----
    print("\n" + "-" * w)
    print("EXCLUDED")
    print("-" * w)
    reasons = defaultdict(lambda: [0, 0.0])
    for r in rows:
        if r["verdict"] != "candidate":
            reasons[r["verdict"]][0] += 1
            reasons[r["verdict"]][1] += r["size"]
    for reason, (n, size) in sorted(reasons.items(), key=lambda kv: -kv[1][1]):
        print(f"  {reason:<26} {human(size):>9} {n:>7,} files")

    est_n = sum(1 for r in rows if r["audio_est"])
    print("\n" + "-" * w)
    print("Savings are estimates: they assume the target bitrate is acceptable for")
    print("the content. Least reliable on grainy film scans, which HEVC NVENC")
    print("handles worst. Encode a few and compare before trusting these totals.")
    if est_n:
        print(f"Audio bitrate was absent from the container on {est_n:,} of "
              f"{len(rows):,} files")
        print("and estimated from codec and channel count.")
    print("-" * w)

    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8") as fh:
            wtr = csv.writer(fh)
            wtr.writerow(["saving_gb", "size_gb", "mbps", "target_mbps",
                          "codec", "height", "group", "path"])
            for r in sorted(cands, key=lambda r: -r["saving"]):
                wtr.writerow([f"{r['saving'] / GiB:.2f}", f"{r['size'] / GiB:.2f}",
                              f"{r['vbr'] / 1e6:.2f}", f"{r['target'] / 1e6:.2f}",
                              r["vcodec"], r["height"], r["group"], r["path"]])
        print(f"\nwrote {len(cands):,} candidates to {args.csv}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
