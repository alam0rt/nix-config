#!/usr/bin/env python3
"""Render a stroked star polygon to an RGBA PNG.

A star polygon {n/k} places n vertices evenly on a circle and connects each one
to the vertex k steps away. When gcd(n, k) is 1 the result is a single closed
path; otherwise it decomposes into gcd(n, k) separate component polygons drawn
on top of each other. Only the outlines are stroked, so the interior edges stay
visible rather than filling into a solid blob.

Antialiasing is analytic: each pixel's coverage comes from its distance to the
nearest stroke centreline, which is both sharper and far cheaper than
supersampling.

Written to avoid any image library, so it needs nothing but the stdlib.
"""

import argparse
import math
import struct
import zlib


def distance_to_segment(px, py, ax, ay, bx, by):
    """Shortest distance from (px, py) to the segment (ax, ay)-(bx, by)."""
    dx, dy = bx - ax, by - ay
    length_sq = dx * dx + dy * dy
    if length_sq == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length_sq))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def edges(points, skip, centre, radius):
    """The {n/k} edge list, as coordinate pairs."""
    verts = [
        (
            centre + radius * math.cos(math.radians(90 + i * 360.0 / points)),
            centre - radius * math.sin(math.radians(90 + i * 360.0 / points)),
        )
        for i in range(points)
    ]
    return [
        (verts[i][0], verts[i][1], verts[(i + skip) % points][0], verts[(i + skip) % points][1])
        for i in range(points)
    ]


def render(size, points, skip, rgb, stroke):
    centre = size / 2.0
    radius = size * 0.42  # leaves a margin so the points aren't clipped
    half = size * stroke / 2.0
    segments = edges(points, skip, centre, radius)
    red, green, blue = rgb

    rows = []
    for y in range(size):
        py = y + 0.5
        row = bytearray([0])  # PNG per-scanline filter byte: none
        for x in range(size):
            px = x + 0.5
            nearest = min(distance_to_segment(px, py, *s) for s in segments)
            # Coverage falls off over roughly one pixel either side of the edge.
            coverage = max(0.0, min(1.0, half - nearest + 0.5))
            row += bytes((red, green, blue, int(255 * coverage + 0.5)))
        rows.append(bytes(row))
    return b"".join(rows)


def png(size, raw):
    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--size", type=int, default=512, help="output edge length in pixels")
    ap.add_argument("--points", type=int, default=5, help="n: vertices on the circle")
    ap.add_argument("--skip", type=int, default=2, help="k: how far each edge reaches")
    ap.add_argument("--color", default="ffffff", help="stroke colour, rrggbb")
    ap.add_argument("--stroke", type=float, default=0.05, help="stroke width as a fraction of --size")
    ap.add_argument("--out", required=True, help="destination path")
    args = ap.parse_args()

    if args.points < 3:
        ap.error("--points must be at least 3")
    if not 0 < args.skip < args.points:
        ap.error("--skip must be between 1 and --points minus 1")

    rgb = tuple(int(args.color[i : i + 2], 16) for i in (0, 2, 4))
    with open(args.out, "wb") as fh:
        fh.write(png(args.size, render(args.size, args.points, args.skip, rgb, args.stroke)))


if __name__ == "__main__":
    main()
