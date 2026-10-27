#!/usr/bin/env python3
"""mkthrobber.py SIZE FRAMES DIR: the boot splash spinner, DIR/throbber-NNNN.png.

A violet (#8B5CF6) arc with a fading tail going round once over the frames,
on a faint full ring. Pure Python; writes RGBA PNGs.
"""
import math, os, struct, sys, zlib

n, frames, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
c = (n - 1) / 2
radius, width = 0.40 * n, 0.07 * n
violet = (139, 92, 246)


def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


for i in range(frames):
    head = 2 * math.pi * i / frames
    rows = []
    for y in range(n):
        row = bytearray(b"\0")
        for x in range(n):
            d = math.hypot(x - c, y - c)
            edge = max(0.0, min(1.0, width / 2 - abs(d - radius) + 0.5))  # antialiased band
            # angle behind the head, 0 .. 2pi, clockwise from the top
            behind = (head - math.atan2(x - c, c - y)) % (2 * math.pi)
            tail = max(0.0, 1 - behind / (1.5 * math.pi)) ** 1.1
            a = edge * max(0.12, tail)
            row += bytes((*violet, int(255 * a)))
        rows.append(bytes(row))
    with open(os.path.join(out, f"throbber-{i + 1:04d}.png"), "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))
