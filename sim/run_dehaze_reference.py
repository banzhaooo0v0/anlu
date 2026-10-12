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
    # Fine-step five-eighths-strength reciprocal; divide here independently of RTL LUT.
    extra_q6 = min(48, (40 * (256 - t) + t // 2) // t)
    correction = (abs(value - ATMOSPHERIC_LIGHT) * extra_q6 + 32) // 64
    result = value + correction if value >= ATMOSPHERIC_LIGHT else value - correction
    return max(0, min(255, result))



def main():
    # Hazy neutral pixels are moved away from the fixed atmospheric light,
    # while a bright pixel remains saturated and all outputs stay in range.
    assert dehaze_channel(200, 64) < 200
    assert dehaze_channel(80, 64) < 80
    assert dehaze_channel(255, 255) == 255
    assert dehaze_channel(0, 255) == 0
    # All 256x256 channel/dark pairs: clipping and bounded adjacent gain steps.
    max_jump = 0
    for dark in range(256):
        assert 64 <= transmission(dark) <= 256
        for value in range(256):
            result = dehaze_channel(value, dark)
            assert 0 <= result <= 255
            if dark:
                max_jump = max(max_jump, abs(result - dehaze_channel(value, dark-1)))
    assert max_jump <= 4, max_jump
    print(f"gain continuity: max one-code dark change = {max_jump} output codes")

    # The RTL uses the minimum across four RGB pixels for one group dark value.
    assert dark_group([(100, 90, 80), (220, 210, 200), (180, 170, 160), (10, 20, 30)]) == 10
    print("dehaze reference: PASS")


if __name__ == "__main__":
    main()
