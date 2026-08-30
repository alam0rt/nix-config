# Tdarr on sauron

Service config lives in [`nixos/sauron/tdarr`](../../nixos/sauron/tdarr). This
directory holds the things Tdarr keeps in its own database and Nix cannot
declare — flows, and the settings you have to click.

## Why the node starts paused

Tdarr transcoding is **destructive**. It re-encodes a file and replaces the
original on disk. This is not Jellyfin's live transcoding, which is temporary
and thrown away. There is no undo.

Everything here is built around that: the node ships paused, with zero CPU
transcode workers and zero healthcheck workers, and nothing runs until work is
queued by hand.

## Manual setup after a rebuild

Two things the NixOS module cannot set for you:

1. **Transcode cache path → `/srv/tdarr-cache`.** Nix makes the path writable
   but Tdarr defaults its cache to the node's data dir on the 46 GB NVMe root.
   Set this or you fill `/` instead of using the 300 GB dataset.
2. **Libraries.** Add `/srv/media/movies` and `/srv/media/the_will_collection`.
   Do *not* add `/srv/media/tv` — see below.

## `hevc-nvenc-flow.json`

Import via **Flows → Import**. Targets this box specifically: two NVENC cards,
no AV1 support, no CPU workers.

```
Input File
  → Already HEVC? ──yes──────────────→ Replace Original File (no-op, exits)
       │ no
  → Bitrate worth encoding? ──no─────→ Replace Original File (no-op, exits)
       │ yes (>6 Mbps)
  → NVENC present? ──no──────────────→ Fail Flow
       │ yes
  → Start → Set Video Encoder → 10 Bit Video → CQ/B-frames/AQ
          → Remove Data Streams → Set Container (mkv) → Execute
  → Size sane? (15-125%) ──no────────→ Fail Flow
       │ yes
  → Duration intact? (95-102%) ──no──→ Fail Flow
       │ yes
  → Replace Original File
```

### The two gates that matter

**Bitrate gate (>6 Mbps).** Without it every non-HEVC file gets encoded,
including already-tight x264 encodes where you take real quality loss for
almost no space. Per [TRaSH](https://trash-guides.info/Misc/x265-4k/), x265
only pays off from source-quality or remux material — this gate is what keeps
the flow pointed at remuxes.

**Size + duration validation.** These are the only safety net in front of the
destructive replace. Duration is the important one: it catches an encode that
did 8 minutes of a 2-hour film and still exited 0. Every failure path routes to
`Fail Flow`, which leaves the original untouched — the original is only ever
touched by `Replace Original File`.

`Already HEVC → Replace Original File` looks wrong but is correct and
idiomatic. That node documents "if the file hasn't changed then no action is
taken", so it is how a skip branch terminates cleanly as *completed,
unchanged*.

### Encoder settings, and why they differ from the defaults

| Setting | Default | Here | Reason |
|---|---|---|---|
| `ffmpegPreset` | `fast` | `slow` | `fast` is ~NVENC p2/p3, tuned for realtime. This is a one-time archival encode on idle cards — spend the time. |
| `ffmpegQualityEnabled` | `true` | `false` | The quality field emits `-qp` on GPU, i.e. constant-QP, which stops AQ and lookahead redistributing bits. Replaced by `-cq` below. |
| `hardwareType` | `auto` | `nvenc` | If auto-detect ever misses you fall back to `libx265` on a Zen 1 EPYC, occupying a GPU worker at a few fps. |
| `forceEncoding` | `true` | `false` | Belt-and-braces against HEVC→HEVC generation loss if the graph is ever rewired. |

Custom output arguments:

```
-rc vbr -cq 24 -bf 4 -spatial-aq 1 -temporal-aq 1 -rc-lookahead 32
```

`-bf 4` matters — the encoder node emits no B-frames at all, which costs 5-10%
size for nothing. Try `-cq 26` for 2160p.

### Hardware limits

`av1_nvenc` reports **"No capable devices found"** on both cards. The T1000 is
Turing and the RTX A1000 is Ampere; NVENC AV1 encode starts at Ada. HEVC is the
ceiling — do not build a flow around AV1.

## Choosing the format

[`format-choice.md`](format-choice.md) covers why the target is HEVC, what it
costs at playback time, and when AV1 would be worth revisiting. Nothing is
enabled yet.

## Running it

1. Queue **one** file by hand. Watch the transcode tab for the assembled ffmpeg
   command and confirm `-cq` and `-bf 4` actually made it in, and that output
   lands in `/srv/tdarr-cache` and not on `/`.
2. Pilot on 3-4 AVC remuxes. **Copy the originals aside first.** Compare sizes
   and watch them on the largest screen in the house.
3. Only then work down the list in batches, unpausing per batch.

Check Radarr's quality profiles will not read the shrunken files as a downgrade
and re-fetch them — that spends the space twice and silently undoes the work.

## Why `tv` is excluded

It is the biggest tree at 14 TB, but it is already-compressed episodic content:
modest saving, real quality cost, across tens of thousands of files. It is also
the library most likely to be re-grabbed at higher quality afterwards, spending
the space twice. Not configuring it is a stronger guarantee than configuring it
and not queueing it.
