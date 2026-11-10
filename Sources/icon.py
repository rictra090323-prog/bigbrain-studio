"""Render a small, dependency-free radar icon for the macOS bundle."""
import math
import struct
import sys
import zlib

size = 512
pixels = bytearray()
for y in range(size):
    pixels.append(0)
    for x in range(size):
        ox, oy = x - 255.5, y - 255.5
        d = math.hypot(max(abs(ox) - 147, 0), max(abs(oy) - 147, 0))
        opacity = round(255 * max(0, min(1, 70.5 - d)))
        hue = (x + (size - y)) / (size * 2)
        r, g, b = (int(c + hue * k) for c, k in ((22, 50), (30, 42), (72, 85)))
        radius = math.hypot(ox, oy)
        if min(abs(radius - ring) for ring in (93, 140, 181)) < 1.2:
            r, g, b = 67, 74, 110
        if math.hypot(ox - 116, oy + 103) < 6:
            r, g, b = 207, 252, 127
        u, v = (ox - oy * 0.12) / 125, (oy + ox * 0.12) / 141
        if (abs(u) ** 0.58 + abs(v) ** 0.58) <= 1:
            r, g, b = 207, 252, 127
        pixels.extend((r, g, b, opacity))


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


png = (
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(pixels))
    + chunk(b"IEND", b"")
)
with open(sys.argv[1], "wb") as handle:
    handle.write(b"icns" + struct.pack(">I", 16 + len(png)))
    handle.write(b"ic09" + struct.pack(">I", 8 + len(png)) + png)
