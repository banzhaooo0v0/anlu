"""Exhaustively prove unsigned DSP lane isolation, including rounding.

This is an arithmetic proof, not a substitute for the streaming RTL scoreboard
or TD mapping/timing reports. Tests all 6-bit extra gains (including 49..63).
"""
import json


def main():
    count = 0
    for extra in range(64):
        gain = 64 + extra
        for high in range(256):
            high_round = 32 if high >= 240 else 31
            expected_high = high * gain + high_round
            for low in range(256):
                low_round = 32 if low >= 240 else 31
                packed = ((high << 15) | low) * gain + (high_round << 15) + low_round
                assert packed < (1 << 30)
                assert packed >> 15 == expected_high
                assert packed & 0x7fff == low * gain + low_round
                count += 1
    # Prove the rearrangement preserves signed half-away-from-zero rounding
    # for every supported A, every input byte and every extra gain code.
    affine_count = 0
    for atmospheric in range(256):
        for value in range(256):
            positive = value >= atmospheric
            for extra in range(64):
                correction = (abs(value-atmospheric)*extra+32)//64
                original = value + correction if positive else value - correction
                affine = (value*(64+extra)-atmospheric*extra+(32 if positive else 31))//64
                assert original == affine
                affine_count += 1
    result = dict(status="PASS", packing_combinations=count,
                  affine_equivalence_combinations=affine_count, pixel_bits=8,
                  total_gain_bits=7, lane_spacing=15, packed_input_bits=23,
                  packed_product_bits=30, rounding="32 if I>=A else 31",
                  max_lane_product_including_rounding=255*127+32)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
