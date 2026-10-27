#!/usr/bin/env python3
"""mkpng.py RRGGBB[AA] WIDTH HEIGHT OUT.png: a solid-color PNG (GRUB theme pieces)."""
import struct, sys, zlib

color, w, h, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
px = bytes.fromhex(color)
ctype = 6 if len(px) == 4 else 2


def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


raw = b"".join(b"\0" + px * w for _ in range(h))
with open(out, "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
