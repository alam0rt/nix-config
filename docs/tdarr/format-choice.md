# Why HEVC, and why not AV1 or plain H.264

Nothing here is enabled yet. This documents the reasoning behind the target
format before any of the library is rewritten. See
[`README.md`](README.md) for the flow and the safety gates.

## Status

No transcoding is running. As of the last check:

- `sauron-nvenc` has ever completed **zero** transcodes.
- Every file in both libraries is marked `Not required` — 1501 of them —
  except one hand-queued test file (a Blu-ray remux) which is sitting in
  `Transcode error` after failing before ffmpeg was ever invoked.
- `movies` has `processTranscodes` on only because of that single test;
  `the_will_collection` is off.

The library is currently 361 h264, 193 hevc, 6 av1, 3 vc1, 1 mpeg4.

## The constraint that decides it

`av1_nvenc` reports "No capable devices found" on both cards. The T1000 is
Turing, the RTX A1000 is Ampere, and NVENC AV1 **encode** starts at Ada. AV1 on
this box therefore means SVT-AV1 on the CPU, and the node runs with
`transcodeCPU = 0` deliberately — a Zen 1 EPYC doing software AV1 turns a pilot
into a week-long grind.

So the real choice is HEVC or nothing.

## Why HEVC is the right target anyway

**Space.** Roughly 30-50% smaller than H.264 at equivalent perceptual quality.
That is the entire point: mordor sits around 88-91% full, and the reclaim is
concentrated in a minority of very large files.

**Playback.** Hardware HEVC decode is near-universal from ~2015 onward —
phones, TVs, Apple devices, and both cards in this box. Jellyfin can direct-play
it instead of spending GPU on a live transcode for every stream. This matters
more than the encode-side cost, because the encode happens once and playback
happens forever.

## What HEVC costs

**Browsers are the weak spot.** Chrome only decodes HEVC where the OS and GPU
provide it, and Firefox's support is patchier still. Converting an h264 file to
HEVC can *push* web-client playback into server-side transcoding — spending GPU
on every stream to save disk once. Worth knowing how people actually watch
before doing anything at scale. AV1 would be worse here, not better.

> **Since measured.** A year of playback data confirms the concern and puts
> numbers on it: the LG TV, Chromecast, and Firefox never accept HEVC as a
> transcode target, and the LG alone accounts for 242 video encodes. See
> [`h264-alternative.md`](h264-alternative.md), which also finds that a
> remux-focused gate makes H.264 capture ~79% of HEVC's reclaim.

**NVENC is not x265.** NVENC HEVC is fast but less efficient per bit than a good
software x265 encode; it needs a somewhat higher bitrate for the same
perceptual result. Since the flow replaces originals in place, that difference
is permanent. This is why the flow uses `slow` rather than `fast`, and `-cq`
with AQ and lookahead rather than constant-QP — see the encoder table in the
README.

**Generation loss.** Re-encoding an already-compressed h264 WEB-DL compounds
artifacts and saves less than the codec comparison suggests. Re-encoding a
Blu-ray remux is the opposite case: a near-lossless source, and a very large
win. This is exactly what the >6 Mbps bitrate gate in the flow is for — it
keeps the work pointed at remuxes and away from tight x264 encodes.

## When to revisit

If an Ada-or-newer card ever lands in this box, AV1 becomes the better target:
another ~20-30% over HEVC. It is not worth chasing today — client-side AV1
decode is still thin enough that it would trade disk savings for a permanent
playback transcoding tax.
