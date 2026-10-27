#!/usr/bin/env python3
"""mklogo.py SIZE OUT.png: the BlankOS mark (violet rings and glow), RGBA."""
import math, struct, sys, zlib

n, out = int(sys.argv[1]), sys.argv[2]
c = (n - 1) / 2
rows = []
for y in range(n):
    row = bytearray(b"\0")
    for x in range(n):
        d = math.hypot(x - c, y - c) / (n / 2)  # 0 centre .. 1 edge
        glow = max(0.0, 1 - d / 0.55) ** 1.5
        ring = max(0.0, 1 - abs(d - 0.78) / 0.07)
        a = min(1.0, glow + ring)
        r, g, b = (139 + (196 - 139) * glow, 92 + (181 - 92) * glow, 246 + (253 - 246) * glow)
        row += bytes((int(r), int(g), int(b), int(255 * a)))
    rows.append(bytes(row))


def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


with open(out, "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))
