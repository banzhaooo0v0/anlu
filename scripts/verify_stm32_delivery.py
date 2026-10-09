"""Check copied inputs, allowed diffs and the generated firmware artifacts."""
from pathlib import Path
import hashlib
import json
import struct
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parents[1] / "stm32"
COPY = HERE / "WHEELTEC_C50X_FPGA_PD89"
manifest = json.loads((HERE.parent / "docs/stm32_delivery_sha256.json").read_text(encoding="utf-8"))
for rel, expected_hash in manifest["files"].items():
    p = COPY / rel
    assert p.is_file(), f"Missing delivered file {rel}"
    assert hashlib.sha256(p.read_bytes()).hexdigest() == expected_hash, f"Delivery hash mismatch {rel}"
count = len(manifest["files"])
observed = []  # No STM32 vendor source changes made in this integration.
project = COPY / "USER/WHEELTEC.uvprojx"
tree = ET.parse(project)
target_inputs = {}
for target in tree.findall("./Targets/Target"):
    files = target.findall("./Groups/Group/Files/File")
    for file in files:
        path = project.parent / file.findtext("FilePath").replace("\\", "/")
        assert path.exists(), f"Missing project input {path}"
    target_inputs[target.findtext("TargetName")] = len(files)

out = COPY / "OBJ/cli_4WD"
binary = (out / "4WD_Car_FPGA_PD89.bin").read_bytes()
sp, reset = struct.unpack_from("<II", binary)
assert 0x20000000 <= sp <= 0x20020000, hex(sp)
assert reset & 1, "Cortex-M reset PC must select Thumb"
assert 0x08000000 <= (reset & ~1) < 0x08000000 + len(binary), hex(reset)
assert len(binary) <= 0x80000
memory = {}
base = 0
eof = False
records = 0
for line in (out / "4WD_Car_FPGA_PD89.hex").read_text().splitlines():
    assert line.startswith(":"), line
    row = bytes.fromhex(line[1:])
    assert len(row) == row[0] + 5
    assert sum(row) & 0xFF == 0, "Invalid Intel HEX record checksum"
    records += 1
    address = (row[1] << 8) | row[2]
    kind = row[3]
    if kind == 4:
        base = int.from_bytes(row[4:6], "big") << 16
    elif kind == 0:
        for index, value in enumerate(row[4:-1]):
            absolute = base + address + index
            assert 0x08000000 <= absolute < 0x08080000
            assert absolute not in memory
            memory[absolute] = value
    elif kind == 1:
        eof = True
assert eof
assert len(memory) == len(binary)
assert bytes(memory[0x08000000 + i] for i in range(len(binary))) == binary
result = {"checked_source_files": count, "changed_source_files": observed,
          "project_inputs": target_inputs, "flash_start": "0x08000000",
          "initial_sp": hex(sp), "reset_handler": hex(reset), "binary_bytes": len(binary),
          "intel_hex_records": records,
          "bin_sha256": hashlib.sha256(binary).hexdigest(),
          "hex_sha256": hashlib.sha256((out / "4WD_Car_FPGA_PD89.hex").read_bytes()).hexdigest(),
          "upstream_commit": manifest["upstream_commit"], "status": "PASS; upstream artifact integrity only, not a local ARMCC build or hardware test"}
(HERE.parent / "reports/stm32_delivery_20261009.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
print(json.dumps(result, indent=2, ensure_ascii=False))
