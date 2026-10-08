"""Create a byte-preserving vendor project copy and a minimal UART/safety patch."""
from pathlib import Path
import difflib
import hashlib
import json
import shutil
import xml.etree.ElementTree as ET

SOURCE = Path(r"D:\qrsfpga\car\analysis_work\source\WHEELTEC_C50X_2025.12.26")
HERE = Path(__file__).resolve().parent
DEST = HERE / "WHEELTEC_C50X_FPGA_PD89"

def ignore(directory, names):
    return [n for n in names if n in {"OBJ", ".vscode", "DebugConfig"}
            or n.endswith((".uvguix.Administrator", ".uvguix.fa", ".uvguix.Mayn", ".uvguix.Riooo", ".uvguix.WHEELTEC"))
            or Path(n).suffix.lower() in {".hex", ".bin", ".axf", ".o", ".d", ".crf", ".lnp", ".map"}]

if DEST.exists():
    raise SystemExit(f"Refusing to replace existing copy: {DEST}")
shutil.copytree(SOURCE, DEST, ignore=ignore)
(DEST / "OBJ").mkdir(exist_ok=True)

changes = {}
def replace_exact(rel, old, new):
    path = DEST / rel
    before = path.read_bytes()
    if before.count(old) != 1:
        raise RuntimeError(f"Expected one occurrence in {rel}: {old!r}")
    path.write_bytes(before.replace(old, new))
    changes.setdefault(rel, SOURCE.joinpath(rel).read_bytes())

uart = "HARDWARE/Inc/uartx.h"
replace_exact(uart, b"#if 1 //PB10", b"#if 0 //PB10")
replace_exact(uart, b"#define UART3_PIN_TX        GPIO_Pin_8", b"#define UART3_TX_PIN        GPIO_Pin_8")
replace_exact(uart, b"#define UART3_PIN_RX        GPIO_Pin_9", b"#define UART3_RX_PIN        GPIO_Pin_9")
security_line = next(line for line in (SOURCE / "SYSTEM/sys/sys.c").read_bytes().splitlines(keepends=True)
                     if b"p->SecurityLevel = 1;" in line)
replace_exact("SYSTEM/sys/sys.c", security_line,
    b"\tp->SecurityLevel = 0; // FPGA link: enable command-loss watchdog.\r\n")
replace_exact("BALANCE/balance_task.c", b"robot_control.command_lostcount++;",
    b"/* Saturate the u8 watchdog counter; never wrap back to zero. */\r\n"
    b"\t\t\t\tif( robot_control.command_lostcount <= BALANCE_TASK_RATE )\r\n"
    b"\t\t\t\t\trobot_control.command_lostcount++;")
replace_exact("BALANCE/Inc/balance_task.h", b'#include "bsp_gamepad.h"',
    b'#include "bsp_gamepad.h"\r\n\r\n'
    b'/* Enable only for an explicit factory movement/encoder diagnostic. */\r\n'
    b'#ifndef FPGA_ENABLE_STARTUP_MOTION_CHECK\r\n'
    b'#define FPGA_ENABLE_STARTUP_MOTION_CHECK 0\r\n'
    b'#endif')
replace_exact("BALANCE/balance_task.c", b"        if(CONTROL_DELAY<SysVal.Time_count && SysVal.Time_count<CONTROL_DELAY+200)",
    b"#if FPGA_ENABLE_STARTUP_MOTION_CHECK\r\n"
    b"        if(CONTROL_DELAY<SysVal.Time_count && SysVal.Time_count<CONTROL_DELAY+200)")
replace_exact("BALANCE/balance_task.c", b"\t\t//After the self-check is completed, obtain the control commands for the robot.",
    b"#else\r\n"
    b"        /* No autonomous motion on boot in the FPGA interface package. */\r\n"
    b"        robot_check.check_end = 1;\r\n"
    b"        Drive_Motor(0,0,0);\r\n"
    b"#endif\r\n\r\n"
    b"\t\t//After the self-check is completed, obtain the control commands for the robot.")

patch = []
manifest = []
for rel, before in changes.items():
    after = (DEST / rel).read_bytes()
    patch.extend(difflib.unified_diff(before.decode("gbk").splitlines(keepends=True),
        after.decode("gbk").splitlines(keepends=True), fromfile="a/" + rel, tofile="b/" + rel))
    manifest.append({"path": rel, "original_sha256": hashlib.sha256(before).hexdigest(),
                     "patched_sha256": hashlib.sha256(after).hexdigest()})
(HERE / "uart_pd89_watchdog.patch").write_text("".join(patch), encoding="utf-8", newline="")
(HERE / "patch_manifest.json").write_text(json.dumps({"source": str(SOURCE),
    "copy": str(DEST), "patch_encoding": "UTF-8; vendor C/H files retain original GBK bytes",
    "changes": manifest}, indent=2, ensure_ascii=False), encoding="utf-8")

project = DEST / "USER/WHEELTEC.uvprojx"
tree = ET.parse(project)
missing = []
for target in tree.findall("./Targets/Target"):
    for file in target.findall("./Groups/Group/Files/File"):
        path = project.parent / file.findtext("FilePath").replace("\\", "/")
        if not path.exists():
            missing.append(str(path))
if missing:
    raise RuntimeError(f"Missing project inputs: {missing}")
print(f"Prepared {DEST}; {len(changes)} changed files; all 5 target inputs exist.")
