"""Build the copied 4WD target using local ARMCC 5; never download firmware.

Uses source/include/define lists from the vendor uVision project. It deliberately
does not run the vendor recursive HEX-delete hooks or access the original tree.
"""
from pathlib import Path
import argparse
import json
import subprocess
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
PROJECT = HERE / "WHEELTEC_C50X_FPGA_PD89/USER/WHEELTEC.uvprojx"
parser = argparse.ArgumentParser()
parser.add_argument("--toolchain", default=r"D:\keil5\ARM\ARMCC\bin")
args = parser.parse_args()
tools = Path(args.toolchain)
tree = ET.parse(PROJECT)
target = next(t for t in tree.findall("./Targets/Target") if t.findtext("TargetName") == "4WD_Car")
controls = target.find("./TargetOption/TargetArmAds/Cads/VariousControls")
defines = controls.findtext("Define").split(",")
includes = controls.findtext("IncludePath").split(";")
work = PROJECT.parent
out = work.parent / "OBJ/cli_4WD"
out.mkdir(parents=True, exist_ok=True)
base = [str(tools / "armcc.exe"), "--cpu", "Cortex-M4.fp.sp", "--c99",
        "--apcs=interwork", "-O3", "--split_sections", "-g", "-D", "__MICROLIB"]
for item in defines:
    base += ["-D", item]
for item in includes:
    base += ["-I", item]
lines = []
commands = []
objects = []
def run(command):
    commands.append(command)
    p = subprocess.run(command, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output = p.stdout.decode("gbk", errors="replace")
    lines.append(output)
    if p.returncode:
        (HERE / "build_armcc.log").write_text("".join(lines), encoding="utf-8")
        (HERE / "build_commands.json").write_text(json.dumps(commands, indent=2), encoding="utf-8")
        raise SystemExit(f"Command failed ({p.returncode}): {' '.join(command)}\n{output}")
    return output

run([str(tools / "armcc.exe"), "--vsn"])
sources = target.findall("./Groups/Group/Files/File")
for index, source in enumerate(sources):
    if source.findtext("./FileOption/CommonProperty/IncludeInBuild") == "0":
        continue
    filetype = source.findtext("FileType")
    if filetype not in {"1", "2"}:
        continue
    path = source.findtext("FilePath")
    obj = out / f"{index:03d}_{Path(path.replace(chr(92), '/')).stem}.o"
    if filetype == "1":
        command = base + ["-c", path, "-o", str(obj)]
    else:
        command = [str(tools / "armasm.exe"), "--cpu", "Cortex-M4", "--fpu", "FPv4-SP",
                   "--apcs=interwork", "--pd", "__MICROLIB SETA 1", "-g", path, "-o", str(obj)]
    run(command)
    objects.append(str(obj))

axf = out / "4WD_Car_FPGA_PD89.axf"
scatter = out / "4WD_Car_FPGA_PD89.sct"
scatter.write_text("""LR_IROM1 0x08000000 0x00080000 {
  ER_IROM1 0x08000000 0x00080000 {
    *.o (RESET, +First)
    *(InRoot$$Sections)
    .ANY (+RO)
  }
  RW_IRAM1 0x20000000 0x00020000 {
    .ANY (+RW +ZI)
  }
}
""", encoding="ascii")
run([str(tools / "armlink.exe"), "--cpu", "Cortex-M4.fp.sp", "--entry", "Reset_Handler",
     "--library_type=microlib", "--scatter", str(scatter),
     "--map", "--info", "sizes", "--list", str(out / "4WD_Car_FPGA_PD89.map"),
     "--output", str(axf), *objects])
run([str(tools / "fromelf.exe"), "--i32combined", "--output", str(out / "4WD_Car_FPGA_PD89.hex"), str(axf)])
run([str(tools / "fromelf.exe"), "--bin", "--output", str(out / "4WD_Car_FPGA_PD89.bin"), str(axf)])
lines.append(f"BUILD SUCCESS: {len(objects)} source units; {axf}\n")
(HERE / "build_armcc.log").write_text("".join(lines), encoding="utf-8")
(HERE / "build_commands.json").write_text(json.dumps(commands, indent=2), encoding="utf-8")
print(lines[-1].strip())
