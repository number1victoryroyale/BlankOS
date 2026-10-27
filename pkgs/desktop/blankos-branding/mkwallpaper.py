#!/usr/bin/env python3
"""mkwallpaper.py WIDTH HEIGHT OUT.png: draw the BlankOS wallpaper.

Near-black with a violet (#8B5CF6) glow rising from the lower right, a
deep indigo glow top left and thin violet rings around the main glow.
Pure Python (no image libraries in the build root); writes an RGB PNG.
"""
import math, random, struct, sys, zlib

w, h, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
base = (11, 11, 16)
violet = (139, 92, 246)
indigo = (49, 46, 129)
# glow centres and radii, in pixels
g1 = (0.78 * w, 0.92 * h, 0.95 * h)
g2 = (0.12 * w, 0.05 * h, 0.75 * h)
rings = [0.34 * h, 0.46 * h, 0.60 * h]
ring_width = max(1.5, h / 900)
rnd = random.Random(1)

rows = []
for y in range(h):
    row = bytearray(b"\0")  # PNG filter type 0
    dy1 = (y - g1[1]) ** 2
    dy2 = (y - g2[1]) ** 2
    for x in range(w):
        d1 = math.sqrt((x - g1[0]) ** 2 + dy1)
        d2 = math.sqrt((x - g2[0]) ** 2 + dy2)
        a1 = max(0.0, 1 - d1 / g1[2]) ** 2.2 * 0.85
        a2 = max(0.0, 1 - d2 / g2[2]) ** 2.0 * 0.45
        ring = 0.0
        for r in rings:
            ring = max(ring, max(0.0, 1 - abs(d1 - r) / ring_width) * 0.22 * (1 - d1 / (1.4 * h)))
        n = rnd.random() - 0.5  # dither against banding
        px = []
        for c in range(3):
            v = base[c] + (violet[c] - base[c]) * min(1.0, a1 + ring) + (indigo[c] - base[c]) * a2
            px.append(max(0, min(255, int(v + n))))
        row += bytes(px)
    rows.append(bytes(row))


def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


with open(out, "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n")
    f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
    f.write(chunk(b"IDAT", zlib.compress(b"".join(rows), 9)))
    f.write(chunk(b"IEND", b""))
