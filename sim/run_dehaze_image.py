"""Prepare a real RGB image and reconstruct PNGs ONLY from XSim RTL output."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw
from run_dehaze_reference import dehaze_channel


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("stage", choices=["prepare", "collect"])
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--build", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    im = Image.open(args.input).convert("RGB")
    w, h = im.size
    if w % 4 or w < 12:
        raise ValueError("Image width must be divisible by four and at least 12")
    raw = im.tobytes()
    build, output = args.build, args.output
    build.mkdir(parents=True, exist_ok=True)
    if args.stage == "prepare":
        # Byte 0 is R of the first pixel. Same convention for readback.
        with (build / "image_input.hex").open("w", encoding="ascii") as f:
            for start in range(0, len(raw), 12):
                f.write(raw[start:start+12][::-1].hex() + "\n")
        (build / "image_size.vh").write_text(
            f"`define IMAGE_WIDTH {w}\n`define IMAGE_HEIGHT {h}\n", encoding="ascii")
        print(f"Prepared {w}x{h}, {w*h//4} RGB888 groups; no resizing")
        return

    def decode(name):
        lines = (build / name).read_text(encoding="ascii").splitlines()
        if len(lines) != w*h//4 or any(len(line) != 24 for line in lines):
            raise AssertionError(f"Invalid RTL output length: {name}")
        return b"".join(bytes.fromhex(line)[::-1] for line in lines)

    processed = decode("image_processed.hex")
    original = decode("image_original.hex")
    if original != raw:
        raise AssertionError("RTL bypass differs from source RGB pixels")
    groups = w//4
    dark = [min(raw[i:i+12]) for i in range(0, len(raw), 12)]
    lut = [bytes(dehaze_channel(v, d) for v in range(256)) for d in range(256)]
    expected = bytearray(len(raw))
    for y in range(h):
        for x in range(groups):
            d = min(dark[yy*groups+xx]
                    for yy in range(max(0, y-2), y+1)
                    for xx in range(max(0, x-2), x+1))
            start = (y*groups+x)*12
            expected[start:start+12] = bytes(lut[d][v] for v in raw[start:start+12])
    mismatches = sum(a != b for a, b in zip(processed, expected))
    if mismatches:
        raise AssertionError(f"RTL/reference mismatch: {mismatches} channels")
    output.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.input, output / "Fog_source.png")
    Image.frombytes("RGB", (w,h), original).save(output / "Fog_original_rtl.png")
    result = Image.frombytes("RGB", (w,h), processed)
    result.save(output / "Fog_dehazed_rtl.png")
    comparison = Image.new("RGB", (w*2, h+64), "#162130")
    comparison.paste(im, (0,64))
    comparison.paste(result, (w,64))
    draw = ImageDraw.Draw(comparison)
    draw.text((24,22), "Original / RTL bypass", fill="white", font_size=28)
    draw.text((w+24,22), "Dehazed / RTL output", fill="white", font_size=28)
    comparison.save(output / "Fog_comparison.png")
    preview = comparison.copy()
    preview.thumbnail((1600,900))
    preview.save(output / "Fog_comparison_preview.png")
    rtl = Path(__file__).resolve().parents[1] / "user_source/hdl_source/ip/image/dehaze_stream_96.v"
    metrics = dict(width=w, height=h, pixels=w*h, groups=w*h//4,
                   checked_channels=len(raw), reference_mismatches=mismatches,
                   bypass_exact=True, source_sha256=sha256(args.input), rtl_sha256=sha256(rtl),
                   output_sha256=sha256(output / "Fog_dehazed_rtl.png"),
                   parameters=dict(ATMOSPHERIC_LIGHT=240, OMEGA_Q8=218, MIN_TRANSMISSION=64),
                   mean_rgb_before=sum(raw)/len(raw), mean_rgb_after=sum(processed)/len(processed))
    (output / "verification.json").write_text(json.dumps(metrics, indent=2)+"\n", encoding="utf-8")
    print(f"PASS: {w*h} RTL pixels / {len(raw)} channels match reference; bypass exact")
    print(f"Saved {output / 'Fog_dehazed_rtl.png'}")


if __name__ == "__main__":
    main()
