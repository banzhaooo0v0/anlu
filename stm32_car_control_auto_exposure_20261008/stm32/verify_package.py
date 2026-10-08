"""Check copied inputs, allowed diffs and the generated firmware artifacts."""
from pathlib import Path
import hashlib
import json
import struct
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
manifest = json.loads((HERE / "patch_manifest.json").read_text(encoding="utf-8"))
SOURCE = Path(manifest["source"])
COPY = HERE / "WHEELTEC_C50X_FPGA_PD89"
expected = {item["path"]: item for item in manifest["changes"]}
observed = []
count = 0
for source in SOURCE.rglob("*"):
    if not source.is_file() or source.suffix.lower() not in {".c", ".h", ".s", ".uvprojx"}:
        continue
    rel = source.relative_to(SOURCE).as_posix()
    copy = COPY / rel
    assert copy.exists(), f"Missing copied source {rel}"
    count += 1
    before, after = source.read_bytes(), copy.read_bytes()
    if before != after:
        assert rel in expected, f"Unexpected source modification {rel}"
        assert hashlib.sha256(before).hexdigest() == expected[rel]["original_sha256"]
        assert hashlib.sha256(after).hexdigest() == expected[rel]["patched_sha256"]
        observed.append(rel)
assert set(observed) == set(expected)

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
          "status": "PASS; artifact verification only, no hardware test"}
(HERE / "verification.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
print(json.dumps(result, indent=2, ensure_ascii=False))
