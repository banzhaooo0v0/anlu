"""Independent pixel-coordinate reference for Sobel -> 3x3 binary morphology."""
import argparse
import random
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--width', type=int, default=1280)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
w, h = a.width, 12
rng = random.Random(20261009)
stim, checks = [], []
for frame in range(8):
    mode = (3, 2, 1, 0)[frame % 4]
    threshold = 24 if frame < 4 else 190
    rgb = [[tuple(rng.randrange(256) for _ in range(3)) for x in range(w)] for y in range(h)]
    if frame < 4:
        rgb = [[(240,240,240) if (x//3+y//2)%2 else (8,8,8) for x in range(w)] for y in range(h)]
    gray = [[(77*r+150*g+29*b)>>8 for r,g,b in row] for row in rgb]
    def at(arr, y, x):
        return arr[y][x] if 0 <= y < h and 0 <= x < w else 0
    edge = [[0]*w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            gx = sum(at(gray,y-dy,x)-at(gray,y-dy,x-2) for dy in (0,1,1,2))
            gy = sum(at(gray,y,x-dx)-at(gray,y-2,x-dx) for dx in (0,1,1,2))
            edge[y][x] = int(abs(gx)+abs(gy) > threshold)
    for y in range(h):
        for x in range(0,w,4):
            raw = out = grays = 0
            for lane in range(4):
                r,g,b = rgb[y][x+lane]
                raw |= (r<<16 | g<<8 | b) << (24*lane)
                taps = [at(edge,yy,xx) for yy in range(y-2,y+1) for xx in range(x+lane-2,x+lane+1)]
                bit = (all(taps) if mode==2 else any(taps)) if y>=2 else False
                pixel = (0xffffff if bit else 0) if mode in (1,2) else (r<<16 | g<<8 | b)
                out |= pixel << (24*lane)
                grays |= gray[y][x+lane] << (8*lane)
            first, last = int(x==0 and y==0), int(x==w-4)
            for _ in range(rng.randrange(2)):
                stim.append(0); checks.append(0)
            # Frame config must remain latched despite changes between pixels.
            config = mode if first else mode^3
            thresh_in = threshold if first else 2047
            stim.append(raw | config<<96 | thresh_in<<98 | last<<109 | first<<110 | 1<<111)
            checks.append(out | grays<<96 | mode<<128 | last<<130 | first<<131 | 1<<132)
    for _ in range(8):
        stim.append(0);checks.append(0)
checks = ([0]*3+checks)[:len(stim)]
a.out.mkdir(parents=True,exist_ok=True)
(a.out/'morph_input.hex').write_text(''.join(f'{v:028x}\n' for v in stim))
(a.out/'morph_expected.hex').write_text(''.join(f'{v:034x}\n' for v in checks))
(a.out/'morph_size.vh').write_text(f'`define MORPH_W {w}\n`define MORPH_H {h}\n`define MORPH_N {len(stim)}\n')
print(f'Generated morphology reference: 8 frames {w}x{h}, four independent RGB pixels per beat')
