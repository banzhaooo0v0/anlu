"""Read-only audit of the retained-STM32 TD build and its bitstream.

Usage: python tools/verify_bit.py --output reports/bit_verification.json
       python tools/verify_bit.py --root PACKAGE_DIRECTORY --output REPORT.json

No build, programming, project edit, or binary-header guess is performed.  The
only optional write is the explicitly supplied JSON output.  Exit 0 requires a
complete TD stage-evidence chain, matching device/top, all 66 project inputs,
the 8 integrated car modules, and nonnegative final setup/hold timing.  A file's
nonzero size or the TD process exit code alone never establishes success.
ERROR/FATAL or unclassified CRITICAL diagnostics block success.  All WARNING
and CRITICAL-WARNING lines are retained and produce PASS_WITH_WARNINGS instead
of a clean PASS.  Build verification never establishes hardware operation or
100% timing coverage.  Archived failed/probe sessions are reported separately.
"""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET


CAR_MODULES = {
    "car_uart_tx", "car_uart_rx", "car_command_tx", "car_telemetry_rx",
    "car_result_cdc", "car_button", "car_decision", "car_control",
}
PHYSICAL_STAGES = [
    "CAR_BIT_ELABORATE_OK", "CAR_BIT_RTL_OK", "CAR_BIT_GATE_OK",
    "CAR_BIT_PLACE_OK", "CAR_BIT_ROUTE_OK",
]
EXPECTED_CLOCKS = {
    "sys_clk_50m", "MIPI_RX_BYTE_CLK", "HDMI_PIXEL_CLK", "HDMI_SERIAL_CLK",
    "mipi_rx_ck_pad", "u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk",
    "u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk",
}
STAMP = r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"
NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig", errors="replace") if path.is_file() else ""


def utc_timestamp(stamp: str) -> float:
    return datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()


def fingerprint(path: Path) -> dict:
    info = {"path": str(path), "exists": path.is_file()}
    if path.is_file():
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        stat = path.stat()
        info.update(bytes=stat.st_size, sha256=digest.hexdigest(),
                    modified_utc=datetime.fromtimestamp(stat.st_mtime, timezone.utc).isoformat())
    return info


def field(text: str, label: str) -> str | None:
    # Horizontal whitespace only: an empty Constraint File must stay empty,
    # rather than accidentally consuming the following Confidence line.
    match = re.search(r"^[ \t]*" + re.escape(label) + r"[ \t]*:[ \t]*(.*?)[ \t]*$", text, re.M)
    return match.group(1) if match else None


def flow_metrics(text: str, label: str) -> dict | None:
    match = re.search(r"^\s*" + label + r"\s*:\s*WNS\s+(" + NUMBER +
                      r")\s*(ps|ns)\s+TNS\s+(" + NUMBER +
                      r")\s*(ps|ns)\s+NUM_FEPS\s+(\d+)\b", text, re.M)
    if not match:
        return None
    wns, wunit, tns, tunit, endpoints = match.groups()
    return {"wns_ns": float(wns) / (1000 if wunit == "ps" else 1),
            "tns_ns": float(tns) / (1000 if tunit == "ps" else 1),
            "num_failing_endpoints": int(endpoints), "reported_line": match.group(0).strip()}


def scan_diagnostics(paths: list[Path]) -> dict:
    """Retain every recognized diagnostic occurrence; log/logw may duplicate it."""
    findings = []
    pattern = re.compile(r"^\s*(?:\[[^\]]+\]\s*)?(?:[A-Z][A-Z0-9_]*-\d+\s+)?"
                         r"(CRITICAL(?:[-\s]+WARNING)?|ERROR|FATAL|WARNING)\b", re.I)
    for path in paths:
        for number, line in enumerate(read(path).splitlines(), 1):
            match = pattern.match(line)
            if match:
                severity = re.sub(r"[-\s]+", "-", match.group(1).upper())
                findings.append({"file": str(path), "line": number,
                                 "severity": severity, "message": line})
    counts = Counter(item["severity"] for item in findings)
    errors = counts["ERROR"] + counts["FATAL"]
    warnings = counts["WARNING"] + counts["CRITICAL-WARNING"]
    return {
        "scanned_files": [str(path) for path in paths], "finding_count": len(findings),
        "findings": findings, "error_count": counts["ERROR"], "fatal_count": counts["FATAL"],
        "errors_count": errors, "critical_warning_count": counts["CRITICAL-WARNING"],
        "warning_count": counts["WARNING"], "unclassified_critical_count": counts["CRITICAL"],
        "blocking_error_count": errors + counts["CRITICAL"],
        "warnings_retained": True,
        "warnings": [item for item in findings if item["severity"] in {"WARNING", "CRITICAL-WARNING"}],
        "unique_warning_messages": sorted({item["message"] for item in findings
                                            if item["severity"] in {"WARNING", "CRITICAL-WARNING"}}),
        "requires_manual_context_review": bool(findings),
        "verdict": "FAIL" if errors or counts["CRITICAL"] else ("PASS_WITH_WARNINGS" if warnings else "PASS"),
        "counting_note": "Counts are diagnostic line occurrences, including repeated messages and log/logw duplicates; no warning lines are discarded.",
    }


def audit(root: Path) -> dict:
    report: dict = {"schema_version": 2, "package": str(root),
                    "audited_utc": datetime.now(timezone.utc).isoformat(),
                    "architecture": "FPGA vision/decision/UART; STM32 motor and encoder closed-loop control",
                    "hardware_programmed_or_tested_by_this_tool": False,
                    "checks": [], "limitations": [
                        "Bit binary format, CRC/signature and target silicon are not independently decoded.",
                        "Generation is established by TD stage records, routed reports and matching file metadata; hardware operation is untested.",
                        "Final timing applies to the supplied constraints and reported STA coverage, not to every unconstrained path.",
                        "ERROR/CRITICAL findings in active build logs require contextual review; diagnostics_missing_sdc is separately retained as historical evidence.",
                    ]}

    def check(name: str, passed: bool, detail=None, category="structure"):
        report["checks"].append({"name": name, "category": category, "passed": bool(passed), "detail": detail})

    project = root / "fpga/traffic_sign_td/td_project/traffic_sign_td.al"
    project_dir = project.parent
    report["project_file"] = fingerprint(project)
    inputs = []
    try:
        # TD emits non-XML UsedInP&R values and names containing double colons.
        text = re.sub(r"&(?!#?\w+;)", "&amp;", read(project)).replace("::", "__")
        xml = ET.fromstring(text)
        nodes = xml.findall(".//Source_Files//File")
        report["project_properties"] = {
            "saved_project_directory": xml.attrib.get("Path"),
            "device": xml.findtext("HardWare/Device"),
            "speed": xml.findtext("HardWare/Speed"),
            "top": xml.findtext("TOP_MODULE/MODULE"),
            "td_version": xml.findtext("TD_Version"),
        }
        for node in nodes:
            relative = node.attrib.get("Path", "")
            path = (project_dir / relative).resolve()
            attrs = {n.attrib.get("Name"): n.attrib.get("Val") for n in node.findall("FileInfo/Attr")}
            inputs.append({"entry": relative, "stem": path.stem,
                           "used_in_synthesis": attrs.get("UsedInSyn"),
                           "used_in_physical_design": attrs.get("UsedInP&R"),
                           **fingerprint(path)})
        check("66 AL source/constraint/IP entries exist", len(inputs) == 66 and all(p["exists"] for p in inputs),
              {"count": len(inputs), "missing": [p["entry"] for p in inputs if not p["exists"]]})
        car_inputs = {p["stem"] for p in inputs if p["stem"] in CAR_MODULES and
                      p["used_in_synthesis"] == "true" and p["used_in_physical_design"] == "true"}
        check("8 car RTL modules enabled in AL", car_inputs == CAR_MODULES, sorted(car_inputs))
        props = report["project_properties"]
        check("expected device/speed/top in AL", props["device"] == "PH1P35MDG324" and
              props["speed"] in {"-3", "3"} and props["top"] == "design_top_wrapper", props)
    except (ET.ParseError, OSError) as exc:
        check("AL project parsed", False, str(exc))
    report["project_inputs"] = inputs
    top = read(root / "fpga/traffic_sign_td/user_source/lab_ex_2026_nosoft/hdl_source/design_top_wrapper.v")
    check("car_control integrated through UART in top", bool(
        re.search(r"\bcar_control\s*(?:#\s*\(.*?\)\s*)?u_car_control\s*\(", top, re.S)
        and re.search(r"\.rx\s*\(\s*I_car_rx\s*\)", top)
        and re.search(r"\.tx\s*\(\s*O_car_tx\s*\)", top)))

    output_dir = root / "integration/td_bit"
    route_path = output_dir / "route_flow.status"
    timing_path = output_dir / "traffic_sign_td_pr.timing"
    route = read(route_path)
    timing = read(timing_path)
    route_info = {"file": fingerprint(route_path), "device": field(route, "Device"),
                  "speed": field(route, "Speed"), "top": field(route, "Top Model"),
                  "timing_mode": field(route, "Timing Mode"),
                  "setup": flow_metrics(route, "Setup"), "hold": flow_metrics(route, "Hold")}
    report["route_flow"] = route_info
    check("final routed flow matches device/top", route_info["timing_mode"] == "final" and
          route_info["device"] == "PH1P35MDG324" and route_info["speed"] == "3" and
          route_info["top"] == "design_top_wrapper", route_info, category="timing")
    for kind in ("setup", "hold"):
        metrics = route_info[kind]
        check(f"final {kind} WNS/TNS/NUM_FEPS pass", metrics is not None and
              metrics["wns_ns"] >= 0 and metrics["tns_ns"] == 0 and
              metrics["num_failing_endpoints"] == 0, metrics, category="timing")
    values = {}
    # Read only the global Timing Status preceding the clock and per-path tables.
    global_timing = timing.split("Clock Summary", 1)[0]
    for name in ("SWNS", "STNS", "HWNS", "HTNS"):
        match = re.search(r"\b" + name + r"\s*:\s*(" + NUMBER + r")\s*ns\b", global_timing)
        values[name] = float(match.group(1)) if match else None
    period_match = re.search(r"Period Check WNS\s*:\s*(" + NUMBER + r")\s*ns\b", global_timing)
    timing_info = {"file": fingerprint(timing_path), "device": field(timing, "Device"),
                   "speed": field(timing, "Speed"), "top": field(timing, "Top Model"),
                   "confidence": field(timing, "Confidence"), "sta_coverage": field(timing, "STA coverage"),
                   "constraint_file": field(timing, "Constraint File"),
                   "global_timing_ns": values,
                   "period_check_wns_ns": float(period_match.group(1)) if period_match else None}
    clock_section = timing.split("Clock Summary", 1)[1] if "Clock Summary" in timing else ""
    clock_section = re.split(r"(?m)^\s*Notes\s*$", clock_section, maxsplit=1)[0]
    clocks = re.findall(r"(?m)^\s*clk\d+\s*:\s*[\d.]+\s+\d+\s+(\S+)\s*$", clock_section)
    timing_info["clock_names"] = clocks
    report["routed_timing"] = timing_info
    check("routed timing summary matches device/top", timing_info["confidence"] == "Routed" and
          timing_info["device"] == "PH1P35MDG324" and timing_info["speed"] == "3" and
          timing_info["top"] == "design_top_wrapper", timing_info, category="timing")
    check("main traffic_sign_td.sdc appears in routed Constraint File", bool(timing_info["constraint_file"] and
          "traffic_sign_td.sdc" in timing_info["constraint_file"]), timing_info["constraint_file"], category="timing")
    check("real camera/HDMI/system/DDR clocks appear in Clock Summary", EXPECTED_CLOCKS <= set(clocks),
          {"required": sorted(EXPECTED_CLOCKS), "observed": clocks, "missing": sorted(EXPECTED_CLOCKS - set(clocks))}, category="timing")
    check("global routed timing passes", all(v is not None and math.isfinite(v) for v in values.values()) and
          values["SWNS"] >= 0 and values["HWNS"] >= 0 and values["STNS"] == 0 and values["HTNS"] == 0 and
          timing_info["period_check_wns_ns"] is not None and timing_info["period_check_wns_ns"] >= 0, values, category="timing")
    consistent = all(route_info[kind] is not None and values[wns] is not None and values[tns] is not None and
                     abs(route_info[kind]["wns_ns"] - values[wns]) <= .002 and
                     abs(route_info[kind]["tns_ns"] - values[tns]) <= .002
                     for kind, wns, tns in [("setup", "SWNS", "STNS"), ("hold", "HWNS", "HTNS")])
    check("flow and timing summaries agree within 2 ps", consistent, category="timing")

    stage_files = sorted(output_dir.glob("stages_*.log"))
    stage_reports, events = [], []
    for path in stage_files:
        entries = []
        for number, line in enumerate(read(path).splitlines(), 1):
            match = re.match(r"(CAR_BIT_\w+)(?:\s+bytes=(\d+))?\s+(" + STAMP + r")\s*$", line)
            if match:
                event = {"marker": match.group(1), "bytes": int(match.group(2)) if match.group(2) else None,
                         "utc": match.group(3), "file": str(path), "line": number}
                entries.append(event)
                events.append(event)
        stage_reports.append({"file": fingerprint(path), "events": entries,
                              "failure_lines": [line for line in read(path).splitlines() if "CAR_BIT_BUILD_FAILED" in line]})
    report["stage_records"] = stage_reports
    check("initial stages_all.log exists", (output_dir / "stages_all.log").is_file(), category="generation")
    bitgens = sorted([e for e in events if e["marker"] == "CAR_BIT_BITGEN_OK"], key=lambda e: e["utc"])
    final_bitgen = bitgens[-1] if bitgens else None
    build_complete = final_bitgen is not None and any(e["marker"] == "CAR_BIT_BUILD_OK" and
                         e["file"] == final_bitgen["file"] and e["line"] > final_bitgen["line"] for e in events)
    # A single all-stage session or checkpoint resumes may supply this chain.
    chain = []
    if final_bitgen:
        for stage in PHYSICAL_STAGES:
            candidates = [e for e in events if e["marker"] == stage and e["utc"] <= final_bitgen["utc"]]
            if candidates:
                chain.append(max(candidates, key=lambda e: e["utc"]))
    check("complete ordered elaboration-to-route stage chain", len(chain) == len(PHYSICAL_STAGES) and
          all(chain[i]["utc"] <= chain[i + 1]["utc"] for i in range(len(chain) - 1)), chain, category="generation")
    check("bitgen and build completion markers in same final session", build_complete, final_bitgen, category="generation")
    resumed = [item for item in stage_reports if Path(item["file"]["path"]).name == "stages_bitgen.log"]
    report["bitgen_resume_records"] = resumed
    if resumed:
        check("explicit bitgen resume completed", any(
            any(e["marker"] == "CAR_BIT_BITGEN_OK" for e in item["events"]) and
            any(e["marker"] == "CAR_BIT_BUILD_OK" for e in item["events"]) for item in resumed), category="generation")

    bit_path = project_dir / "bitstream/traffic_sign_td_task2_keys_qmark.bit"
    bit = fingerprint(bit_path)
    report["bitstream"] = bit
    compressed_path = project_dir / "bitstream/traffic_sign_td_task2_keys_qmark_compress.bit"
    compressed_bit = fingerprint(compressed_path)
    report["compressed_bitstream"] = compressed_bit
    check("compressed bitstream exists and is nonempty", compressed_bit.get("bytes", 0) > 0,
          compressed_bit, category="generation")
    check("bit size matches TD bitgen completion record", bit.get("bytes", 0) > 0 and
          final_bitgen is not None and bit.get("bytes") == final_bitgen["bytes"],
          {"bit_file_bytes": bit.get("bytes"), "td_recorded_bytes": final_bitgen["bytes"] if final_bitgen else None}, category="generation")
    if bit["exists"] and final_bitgen:
        # Marking follows bitgen immediately.  Five seconds permits timestamp precision.
        check("bit timestamp matches final generation event", abs(bit_path.stat().st_mtime - utc_timestamp(final_bitgen["utc"])) <= 5,
              {"file_mtime_utc": bit["modified_utc"], "generation_utc": final_bitgen["utc"]}, category="generation")
        newer_inputs = [p["entry"] for p in inputs if p["exists"] and Path(p["path"]).stat().st_mtime > bit_path.stat().st_mtime + 1]
        check("no AL input was modified after bit generation", not newer_inputs, newer_inputs, category="generation")
    check("compressed bit timestamp matches same final generation", compressed_bit["exists"] and
          final_bitgen is not None and
          abs(compressed_path.stat().st_mtime - utc_timestamp(final_bitgen["utc"])) <= 5,
          {"file_mtime_utc": compressed_bit.get("modified_utc"),
           "generation_utc": final_bitgen["utc"] if final_bitgen else None}, category="generation")
    report["stage_failure_history"] = {
        "entries": [{"file": item["file"]["path"], "message": line}
                    for item in stage_reports for line in item["failure_lines"]],
        "later_final_bitgen_session_completed": build_complete,
        "interpretation": "Earlier stage failure lines are preserved. A subsequent bitgen completion establishes recovery, not that every attempted run was error-free.",
    }

    report["bitgen_parameters"] = {"file": fingerprint(output_dir / "bitgen_param.txt"),
                                   "text": read(output_dir / "bitgen_param.txt")}
    # Scan actual TD diagnostics, not HDL uses of ERROR or prose in documentation.
    logs = sorted(set((root / "integration").glob("td_*.log")) |
                  set((root / "integration").glob("td_*.logw")) |
                  set(output_dir.rglob("*.log")) | set(output_dir.rglob("*.logw")))
    active_diagnostics = scan_diagnostics(logs)
    report["diagnostic_review"] = active_diagnostics
    # Failed/probe runs that exposed missing SDC are deliberately archived.  They
    # remain visible in this report but do not describe the corrected active run.
    historical_dir = root / "integration/diagnostics_missing_sdc"
    historical_files = sorted(set(historical_dir.rglob("*.log")) | set(historical_dir.rglob("*.logw")))
    report["historical_missing_sdc_diagnostics"] = {
        **scan_diagnostics(historical_files),
        "directory": str(historical_dir), "exists": historical_dir.is_dir(),
        "included_in_active_success_decision": False,
        "reason": "Archived failed/probe runs; active final report must independently show the main SDC and required real clocks.",
    }
    report["generation_and_timing_checks_passed"] = all(item["passed"] for item in report["checks"])
    report["verdicts"] = {
        category: "PASS" if all(item["passed"] for item in report["checks"] if item["category"] == category) else "FAIL"
        for category in ("structure", "generation", "timing")
    }
    report["verdicts"]["diagnostics"] = active_diagnostics["verdict"]
    report["errors_count"] = active_diagnostics["errors_count"]
    report["critical_warning_count"] = active_diagnostics["critical_warning_count"]
    report["warnings_retained"] = True
    report["hardware_validation_required"] = True
    report["passed"] = report["generation_and_timing_checks_passed"] and active_diagnostics["blocking_error_count"] == 0
    report["status"] = "FAIL" if not report["passed"] else active_diagnostics["verdict"]
    report["acceptance_scope"] = "Build artifact and supplied-constraint timing verification only; requires hardware validation and warning review, not a safety/risk-free or complete-STA-coverage certification."
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, help="Explicit JSON report destination; omitted means stdout only")
    args = parser.parse_args()
    report = audit(args.root.resolve())
    encoded = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
        print(f"{report['status']}: {args.output.resolve()}")
        for item in report["checks"]:
            if not item["passed"]:
                print(f"  FAIL: {item['name']}")
        if report["diagnostic_review"]["findings"]:
            diagnostics = report["diagnostic_review"]
            print(f"  DIAGNOSTICS: {diagnostics['errors_count']} ERROR/FATAL, "
                  f"{diagnostics['critical_warning_count']} CRITICAL-WARNING, "
                  f"{diagnostics['warning_count']} WARNING; all retained")
        print("  HARDWARE VALIDATION REQUIRED; STA coverage is limited to the supplied constraints")
    else:
        print(encoded, end="")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
