"""Independent 2D window reference; includes bubbles, frame borders and mode changes."""
import random
from pathlib import Path
from run_dehaze_reference import dehaze_channel

out = Path(__file__).parent / "build_dual"
out.mkdir(exist_ok=True)
rng = random.Random(20261008)
stimulus, expected = [], []
width, height = 64, 8  # groups, not pixels
for frame in range(10):
    dark = []
    for y in range(height):
        dark.append([])
        for x in range(width):
            enabled = frame % 3 != 0
            # Frames 1/2 exercise dense haze and saturation, 4/5 random scenes.
            channels = ([200] * 12 if frame == 1 else
                        [255, 250, 240] * 4 if frame == 2 else
                        # Moving ramps sweep all 256 dark codes; alternate hue and scene cut.
                        [((x + y*width + frame*7) % 256)] * 12 if frame in (6, 7) else
                        [(min(255, ((x*4+y*13) % 224)+i*2)) for i in range(12)] if frame == 8 else
                        [rng.randrange(256) for _ in range(12)])
            dark[y].append(min(channels))
            window = min(dark[yy][xx] for yy in range(max(0, y-2), y+1)
                         for xx in range(max(0, x-2), x+1))
            result = [dehaze_channel(v, window) if enabled else v for v in channels]
            data = sum(v << (i*8) for i,v in enumerate(channels))
            value = sum(v << (i*8) for i,v in enumerate(result))
            first, last = int(x == 0 and y == 0), int(x == width-1)
            # Change enable inside a frame to check first-pixel mode latching.
            enable_input = int(enabled if first else not enabled)
            for _ in range(0 if frame >= 6 else rng.randrange(3)):
                stimulus.append(0)
                expected.append(None)
            stimulus.append(data | enable_input << 96 | last << 97 | first << 98 | 1 << 99)
            expected.append(value | last << 96 | first << 97 | 1 << 98)
for _ in range(12):
    stimulus.append(0)
    expected.append(None)
# S0..S10: an item captured at edge n is output at edge n+10.
checks = [0] * 10 + [v or 0 for v in expected]
checks = checks[:len(stimulus)]
(out / "dehaze_input.hex").write_text("\n".join(f"{v:025x}" for v in stimulus)+"\n")
(out / "dehaze_expected.hex").write_text("\n".join(f"{v:025x}" for v in checks)+"\n")
(out / "dehaze_count.vh").write_text(f"`define DEHAZE_CYCLES {len(stimulus)}\n`define DEHAZE_GROUPS {width*height*10}\n")
print(f"Generated {len(stimulus)} cycles; 5120 valid groups across ten frames, including continuous moving ramps")
