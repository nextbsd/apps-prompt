# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# python3 make-icon.py Terminal.png
#

# Prompt.app's icon: a rounded charcoal tile with a white >_ prompt,
# drawn the way Bluetooth.app's icon is (dark frame, gradient, gloss).
import struct, zlib, math, sys
N = 128; S = 4
def rrect(px, py, x0, y0, x1, y1, r):
    cx = min(max(px, x0+r), x1-r); cy = min(max(py, y0+r), y1-r)
    return math.hypot(px-cx, py-cy) <= r
def near_segment(px, py, ax, ay, bx, by, w):
    dx, dy = bx-ax, by-ay
    t = max(0.0, min(1.0, ((px-ax)*dx + (py-ay)*dy) / (dx*dx + dy*dy)))
    return math.hypot(px-(ax+t*dx), py-(ay+t*dy)) <= w/2
# The prompt: a chevron with round ends, then an underscore cursor.
W = 11
def glyph(px, py):
    if near_segment(px, py, 32, 40, 56, 62, W): return True
    if near_segment(px, py, 56, 62, 32, 84, W): return True
    return rrect(px, py, 64, 79, 96, 89, 3)
rows = []
for y in range(N):
    row = bytearray([0])
    for x in range(N):
        acc = [0.0]*4
        for sy in range(S):
            for sx in range(S):
                px = x + (sx+0.5)/S; py = y + (sy+0.5)/S
                c = (0, 0, 0, 0)
                if rrect(px, py, 8, 8, 120, 120, 22):
                    c = (40, 44, 52, 255)
                    if rrect(px, py, 13, 13, 115, 115, 18):
                        t = (py-13)/102.0          # slate to near black
                        c = (int(92 + (28-92)*t), int(100 + (31-100)*t), int(112 + (38-112)*t), 255)
                        if py < 13 + 40 and px + py < 150:
                            c = tuple(min(255, int(v*0.85 + 255*0.15)) for v in c[:3]) + (255,)
                        if glyph(px, py):
                            c = (255, 255, 255, 255)
                for i in range(4):
                    acc[i] += c[i]
        a = acc[3]/(S*S)
        if a == 0:
            row += bytes(4)
        else:
            row += bytes([int(acc[0]/(acc[3]/255)), int(acc[1]/(acc[3]/255)), int(acc[2]/(acc[3]/255)), int(a)])
    rows.append(bytes(row))
def chunk(t, d):
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t+d) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', N, N, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(png)
