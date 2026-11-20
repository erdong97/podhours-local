#!/usr/bin/env python3
"""Generate a 1024x1024 app icon PNG using only the Python standard library.
Dark navy gradient background, a headphone band arc and two ear cups in a
cyan-to-violet gradient. Run in CI before the Xcode build."""
import math
import struct
import sys
import zlib

SIZE = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def in_rounded_rect(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r or (x0 + r <= x <= x1 - r) or (y0 + r <= y <= y1 - r)


def pixel(x, y):
    # background: vertical gradient
    bg = lerp((7, 10, 20), (27, 34, 66), y / SIZE)
    accent = lerp((125, 211, 252), (167, 139, 250), x / SIZE)

    # headphone band: ring segment centred below middle, upper half only
    cx, cy = SIZE / 2, 590
    dist = math.hypot(x - cx, y - cy)
    if 235 <= dist <= 292 and y < cy - 40:
        return accent
    # ear cups
    if in_rounded_rect(x, y, 218, 470, 368, 760, 62):
        return accent
    if in_rounded_rect(x, y, 656, 470, 806, 760, 62):
        return accent
    return bg


def main():
    out_path = sys.argv[1]
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)  # filter: none
        for x in range(SIZE):
            raw.extend(pixel(x, y))
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    with open(out_path, "wb") as f:
        f.write(png)
    print("icon written:", out_path, len(png), "bytes")


if __name__ == "__main__":
    main()
