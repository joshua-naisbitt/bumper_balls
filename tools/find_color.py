#!/usr/bin/env python3
"""Centre of the pixels near a colour inside a region of a screenshot.

    find_color.py shot.png R,G,B TOL x0,y0,x1,y1   (region as 0..1 fractions)

Prints "x y count" in image pixels, or "none". Used by web_test.mjs to find
on-screen buttons, since the game's UI lives inside a WebGL canvas.
"""
import sys
from PIL import Image

img = Image.open(sys.argv[1]).convert("RGB")
target = [int(v) for v in sys.argv[2].split(",")]
tol = int(sys.argv[3])
fx0, fy0, fx1, fy1 = [float(v) for v in sys.argv[4].split(",")]
w, h = img.size
px = img.load()
xs, ys = [], []
for y in range(int(fy0 * h), int(fy1 * h)):
    for x in range(int(fx0 * w), int(fx1 * w)):
        r, g, b = px[x, y]
        if abs(r - target[0]) <= tol and abs(g - target[1]) <= tol and abs(b - target[2]) <= tol:
            xs.append(x)
            ys.append(y)
if not xs:
    print("none")
else:
    print((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, len(xs))
