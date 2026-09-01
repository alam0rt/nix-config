# H.264 as the target instead of HEVC

Companion to [`format-choice.md`](format-choice.md), which chose HEVC but left
one question open:

> Worth knowing how people actually watch before doing anything at scale.

That is now measured. This document records what the playback data says and
why it makes plain H.264 a defensible target — not because HEVC is wrong, but
because most of the reclaim does not come from the codec.

Nothing here is enabled. As with the HEVC flow, this is reasoning captured
before any of the library is rewritten.

## How people actually watch

Twelve months of the Playback Reporting plugin DB: **14,362 sessions, 32 users,
47 devices, 18 client apps, ~6,600 hours**. Content is 77% episodic.

Filter note: 13 rows carry corrupt negative durations, which is what Playback
Reporting writes when it misses a stop event. Unfiltered they make `Jellyfin
tvOS` report -5.4 million hours. Everything below excludes them.

The fleet splits cleanly on what it will accept as a *transcode target*:

| Device / client | → H.264 | → HEVC |
|---|---:|---:|
| LG Smart TV (Jellyfin for WebOS) | 141 | 0 |
| LG Smart TV (Jellyfin Web) | 200 | 8 |
| Chromecast (Google Cast) | 70 | 0 |
| S21 Ultra (Jellyfin Android) | 23 | 0 |
| Firefox | 63 | 36 |
| Chrome | 6 | 112 |
| Safari (iPhone + desktop) | 0 | 155 |
| iPad (Jellyfin Mobile) | 0 | 67 |
| Android TV / Jellyfin Android TV | 0 | 112 |
| Roku | 0 | 7 |

Two honest qualifications. A client transcoding *to* H.264 does not prove its
hardware cannot decode HEVC — LG panels and Chromecast HD both decode HEVC in
silicon. It proves the **client's declared profile does not offer HEVC as an
HLS transcode target**, and the server pays either way. Firefox is the one real
codec gap: no HEVC decoder on Linux or stock Windows.

And HEVC direct play mostly works *today*: of 240 identifiable HEVC sources in
35 days of ffmpeg command lines, **190 were `-codec:v:0 copy`**.

**The asymmetry is the whole argument.** The library's H.264 files direct-play
on 100% of the fleet right now. Every file the HEVC flow rewrites keeps
direct-playing on Chrome, Safari, Apple TV, Android TV and Roku, but starts
costing a live NVENC encode on the LG, the Chromecast and Firefox. The LG alone
is one user generating **242 video encodes** — the single largest source of
transcode load on the box.

## The gate matters more than the codec

Modelled over 1,088 probed non-HEVC files (5.58 TB — 97% of the 1,116-file
candidate pool), projecting `h264_nvenc -cq 20` against `hevc_nvenc -cq 24`,
capping each file's output at its own source bitrate:

| Bitrate gate | Files | Input | H.264 saves | HEVC saves | HEVC's extra | H.264 as % of HEVC |
|---|---:|---:|---:|---:|---:|---:|
| >6 Mbps (current flow) | 470 | 4.39 TB | 1.02 TB | 1.70 TB | 0.68 TB | 60% |
| >12 Mbps | 152 | 2.26 TB | 0.99 TB | 1.35 TB | 0.36 TB | 73% |
| >15 Mbps | 100 | 1.73 TB | 0.88 TB | 1.12 TB | 0.24 TB | **79%** |

**At a remux-focused gate, H.264 captures 79% of what HEVC captures.** The
codecs converge as the gate tightens, because the win on a 30 Mbps remux is
*being encoded at all* — a 67% cut — and the codec argument is only about
whether the floor is 10 Mbps or 7.5. The 25 largest non-HEVC files measure
24-42 Mbps; that is where the space is.

The library backs this up: 1,501 files / 8.16 TB across `movies` and
`the_will_collection`, with **40% of the bytes in the 207 files over 10 GB**.

If reclaimed space is the only objective, HEVC still wins — by roughly
0.24-0.68 TB depending on the gate. The question is whether that is worth a
permanent live-transcode tax on a third of the fleet.

## The gate is also the idempotency guard

The HEVC flow is safe to re-run because `Already HEVC? → yes → Replace Original
File (no-op)` short-circuits it. **An H.264 flow has no equivalent** — the
remuxes it targets are *already* H.264/AVC, so "already H.264" cannot be a skip
condition.

That makes the bitrate gate load-bearing in a way it is not for HEVC. If the
gate sits below the flow's own output bitrate, the flow re-encodes its own
output on every subsequent run, compounding generation loss silently.

With `-cq 20` landing around 10 Mbps at 1080p, **the gate must be ≥15 Mbps**.
This is a correctness requirement, not a tuning preference. It happens to agree
with [TRaSH](https://trash-guides.info/Misc/x265-4k/), which only endorses
re-encoding from source-quality or remux material.

## Flow changes from `hevc-nvenc-flow.json`

| Node | HEVC flow | H.264 variant |
|---|---|---|
| Skip branch | `Already HEVC?` | **Remove** — cannot work, see above |
| Bitrate gate | `>6 Mbps` | **`>15 Mbps`** — load-bearing |
| Set Video Encoder | `hevc_nvenc` | `h264_nvenc` |
| `10 Bit Video` | present | **Remove** — hard-fails, see below |
| Custom args | `-cq 24` | `-cq 20` |
| Size / duration gates | 15-125% / 95-102% | unchanged |
| Container | mkv | unchanged |

Custom output arguments, assembled and run on the box:

```
-rc vbr -cq 20 -bf 4 -spatial-aq 1 -temporal-aq 1 -rc-lookahead 32 -profile:v high
```

`-cq 20` rather than 24 because the CQ scales are not comparable between
codecs; H.264 needs a lower number for equivalent perceptual quality. Add
`-level 4.1` if targeting the oldest clients — verified to encode cleanly, at
the cost of capping the DPB.

### The 10-bit trap

`ffmpeg -h encoder=h264_nvenc` lists `p010le` among its pixel formats. That
list is generic and wrong for this encoder. Verified on the box rather than
inferred:

```
10-bit (p010le) -> h264_nvenc : Terminating thread with return code -22 (Invalid argument)
                                Conversion failed!
8-bit (yuv420p) -> h264_nvenc : frame=25 ... speed=2.89x
10-bit (p010le) -> hevc_nvenc : frame=25 ... speed=3.05x
```

NVENC has no 10-bit H.264 encode path at all. Carrying the `10 Bit Video` node
across from the HEVC flow makes **every job fail** before producing output.
Harmless in practice for this target set — AVC remuxes are 8-bit — but it fails
loudly and confusingly if left in.

## The lever that beats both codecs

Video codec is not the biggest transcode driver on this box. Audio is.

| Path | Sessions | GPU |
|---|---:|---|
| DirectPlay | 10,402 | none |
| **Transcode, audio→AAC only (`v:direct`)** | **1,641** | **none** |
| Transcode, audio other (`v:direct`) | 1,050 | none |
| Video encode → h264 | 522 | NVENC |
| Video encode → hevc | 531 | NVENC |

**More sessions transcode purely because of audio (1,641) than for video
(1,053 combined.)** These are files whose video is copied untouched while
TrueHD/DTS-HD MA 7.1 is re-encoded to AAC — on every play, forever, across
every client including Android TV (521) which otherwise direct-plays everything.

Jellyfin reports these as "Transcode" in the dashboard, which is how the box
looks busier than it is: the true GPU-encode rate is **7.3%**, not the ~28% a
naive read of `PlaybackMethod` suggests.

A flow that adds a compatible AAC stereo or 5.1 track alongside the lossless
one — or replaces it, on the remuxes where an 7.1 TrueHD track is a meaningful
share of a 30 GB file — removes a larger share of transcodes than any video
codec decision, and is non-destructive to video. Worth its own flow regardless
of which codec wins here.

## Recommendation

Prefer H.264 at a ≥15 Mbps gate, for this box, for three reasons:

1. It captures ~79% of HEVC's reclaim at a remux-focused gate.
2. It keeps 100% of the fleet on direct play permanently, instead of moving a
   third of it onto live NVENC.
3. It is the safer destructive operation — 8-bit only, no client can refuse it,
   and nothing in the library becomes less playable than it is today.

HEVC remains the right answer if the pool gets tight enough that 0.24-0.68 TB
matters more than playback compatibility, or if the LG and the Chromecast leave
the fleet. Revisit if an Ada-or-newer card lands, per
[`format-choice.md`](format-choice.md).

Do the audio flow first either way. It is non-destructive to video, removes
more transcodes than either codec choice, and is independent of this decision.

## Caveats

- Reclaim figures are modelled, not measured: projected output bitrates against
  measured source bitrates and durations. Confirm against the 3-4 file pilot the
  [`README.md`](README.md) already mandates before trusting them at scale.
- The bitrate sample covers 1,088 of 1,116 non-HEVC files; the rest returned no
  duration from ffprobe.
- Playback data reflects the library as it is today — predominantly H.264.
  A fleet that never sees HEVC cannot report trouble with it.
