#!/usr/bin/env python3
"""Generate a 1024x1024 app icon PNG using only the Python standard library.
Blue gradient background with a bold white "P", PodsStats style.
Run in CI before the Xcode build."""
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
    # background: blue vertical gradient
    bg = lerp((24, 88, 216), (66, 152, 255), y / SIZE)
    white = (255, 255, 255)

    # "P" stem
    if 372 <= x <= 468 and 236 <= y <= 788:
        return white
    # "P" bowl: ring to the right of the stem
    dist = math.hypot(x - 566, y - 388)
    if 76 <= dist <= 152 and x >= 372:
        return white
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
