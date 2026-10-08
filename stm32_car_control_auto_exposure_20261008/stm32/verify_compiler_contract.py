"""Check the actual ARMCC preprocessing of UART pins and startup safety gate."""
from pathlib import Path
import json
import re
import subprocess

HERE = Path(__file__).resolve().parent
WORK = HERE / "WHEELTEC_C50X_FPGA_PD89/USER"
commands = json.loads((HERE / "build_commands.json").read_text())
command = next(c for c in commands if "..\\BALANCE\\balance_task.c" in c)
base = command[:command.index("-c")]

def preprocess(source, extra=()):
    p = subprocess.run(base + list(extra) + ["-E", source], cwd=WORK,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert p.returncode == 0, p.stderr.decode(errors="replace")
    return p.stdout.decode("gbk", errors="replace")

def function_body(text, name):
    match = re.search(r"\b" + name + r"\([^;]*?\)\s*\{", text)
    assert match, name
    start = match.end()
    level = 1
    for index in range(start, len(text)):
        if text[index] == "{":
            level += 1
        elif text[index] == "}":
            level -= 1
            if level == 0:
                return text[start:index]
    raise AssertionError("Unterminated function")

normal = function_body(preprocess("..\\BALANCE\\balance_task.c"), "Balance_task")
diagnostic = function_body(preprocess("..\\BALANCE\\balance_task.c", ["-D", "FPGA_ENABLE_STARTUP_MOTION_CHECK=1"]), "Balance_task")
motion = r"Drive_Motor\s*\(\s*0\.2f\s*,\s*0\s*,\s*0\s*\)"
assert not re.search(motion, normal), "Default build contains factory startup motion"
assert re.search(motion, diagnostic), "Explicit diagnostic override was not retained"
assert "robot_check.check_end = 1" in normal

contract = HERE / "uart_pin_contract.c"
contract.write_text('''#include "uartx.h"
typedef char tx_pin_is_pd8[(UART3_TX_PIN == GPIO_Pin_8) ? 1 : -1];
typedef char rx_pin_is_pd9[(UART3_RX_PIN == GPIO_Pin_9) ? 1 : -1];
typedef char tx_af_source_is_8[(UART3_TX_Soure == GPIO_PinSource8) ? 1 : -1];
typedef char rx_af_source_is_9[(UART3_RX_Soure == GPIO_PinSource9) ? 1 : -1];
GPIO_TypeDef *contract_tx_port(void) { return UART3_TX_PORT; }
GPIO_TypeDef *contract_rx_port(void) { return UART3_RX_PORT; }
GPIO_TypeDef *contract_expected_port(void) { return GPIOD; }
''', encoding="ascii")
p = subprocess.run(base + ["-c", str(contract), "-o", str(HERE / "uart_pin_contract.o")],
                   cwd=WORK, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
assert p.returncode == 0, p.stdout.decode(errors="replace") + p.stderr.decode(errors="replace")
ports = preprocess(str(contract))
tx = function_body(ports, "contract_tx_port")
rx = function_body(ports, "contract_rx_port")
expected = function_body(ports, "contract_expected_port")
assert tx.strip() == rx.strip() == expected.strip(), "USART3 port is not GPIOD"
result = {"default_startup_motion_disabled": True, "factory_diagnostic_can_be_explicitly_enabled": True,
          "uart3_tx": "PD8 / AF7", "uart3_rx": "PD9 / AF7",
          "method": "actual ARMCC preprocessing + compile-time pin assertions", "status": "PASS"}
(HERE / "compiler_contract.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print(json.dumps(result, indent=2))
