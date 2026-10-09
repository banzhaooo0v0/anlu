"""Reference checks for the divider-free lightweight dehaze approximation."""

ATMOSPHERIC_LIGHT = 240
OMEGA_Q8 = 218
MIN_TRANSMISSION = 64


def dark_group(pixels):
    return min(min(rgb) for rgb in pixels)


def transmission(dark):
    t = 256 - ((dark * OMEGA_Q8 + 128) >> 8)
    return max(MIN_TRANSMISSION, t)


def dehaze_channel(value, dark):
    t = transmission(dark)
    # RTL shifts an unsigned magnitude, then restores the sign.
    diff = abs(value - ATMOSPHERIC_LIGHT)
    if t >= 240:
        correction = diff
    elif t >= 224:
        correction = diff + (diff >> 4)
    elif t >= 192:
        correction = diff + (diff >> 2)
    elif t >= 160:
        correction = diff + (diff >> 1)
    elif t >= 128:
        correction = diff + (diff >> 1) + (diff >> 2)
    else:
        correction = diff << 1
    signed_correction = correction if value >= ATMOSPHERIC_LIGHT else -correction
    return max(0, min(255, ATMOSPHERIC_LIGHT + signed_correction))


def main():
    # Hazy neutral pixels are moved away from the fixed atmospheric light,
    # while a bright pixel remains saturated and all outputs stay in range.
    assert dehaze_channel(200, 64) < 200
    assert dehaze_channel(80, 64) < 80
    assert dehaze_channel(255, 255) == 255
    assert dehaze_channel(0, 255) == 0
    for dark in range(256):
        assert 64 <= transmission(dark) <= 256
        for value in (0, 32, 96, 160, 224, 255):
            result = dehaze_channel(value, dark)
            assert 0 <= result <= 255

    # The RTL uses the minimum across four RGB pixels for one group dark value.
    assert dark_group([(100, 90, 80), (220, 210, 200), (180, 170, 160), (10, 20, 30)]) == 10
    print("dehaze reference: PASS")


if __name__ == "__main__":
    main()
