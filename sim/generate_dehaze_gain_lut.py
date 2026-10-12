"""Check the RTL's constant gain decoder against exact rational arithmetic."""
from fractions import Fraction
from pathlib import Path
import re

rtl = (Path(__file__).resolve().parents[1] /
       'user_source/hdl_source/ip/image/dehaze_stream_96.v').read_text(encoding='utf-8')
entries = {int(t): int(k) for t, k in re.findall(
    r"10'd(\d+): reciprocal_extra = 6'd(\d+);", rtl)}
for t in range(1, 257):
    exact = Fraction(40 * (256 - t), t)
    rounded = (exact + Fraction(1, 2)).__floor__()
    expected = min(48, rounded)
    actual = entries.get(t, 48)
    assert expected == actual, (t, expected, actual)
assert set(entries) == set(range(103, 257))
print('PASS: 256 V4 gain decoder entries against exact rational reference')
