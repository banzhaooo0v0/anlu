"""Verify copied TD inputs, selected pins, integration and STM32 HEX hash."""
from pathlib import Path
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
project = root / 'fpga/traffic_sign_td/td_project/traffic_sign_td.al'
# TD's AL writer emits a literal ampersand and double-colon property names.
# Normalize those only for the standard-library XML reader, not in the project.
xml = ET.fromstring(project.read_text(encoding='utf-8').replace('UsedInP&R','UsedInP&amp;R').replace('::','__'))
valid_project_paths = {project.parent.resolve().as_posix(), 'D:/qrsfpga/stm32_car_control/fpga/traffic_sign_td/td_project'}
assert xml.attrib['Path'] in valid_project_paths, 'AL project path points outside this package or the canonical delivery'
paths = [n.attrib['Path'] for n in xml.findall('.//File') if 'Path' in n.attrib]
missing = [p for p in paths if not (project.parent / p).is_file()]
assert not missing, f'TD inputs missing: {missing}'
rtl = sorted(p.stem for p in (root / 'rtl').glob('*.v'))
assert len(rtl) == 8, rtl
for name in rtl:
    assert any(Path(p).stem == name for p in paths), f'RTL not in project: {name}'
top = (project.parent / '../user_source/lab_ex_2026_nosoft/hdl_source/design_top_wrapper.v').resolve().read_text(encoding='utf-8')
assert re.search(r'car_control\s*(?:#\(.*?\)\s*)?u_car_control\s*\(', top, re.S), 'Missing integrated car_control instance'
assert re.search(r'\.rx\(I_car_rx\)', top) and re.search(r'\.tx\(O_car_tx\)',top), 'Wrong UART instance connections'
adc = (project.parent / '../user_source/lab_ex_2026_nosoft/constraints_source/pin.adc').resolve().read_text(encoding='utf-8')
for name, pin in {'O_car_tx':'C18','I_car_rx':'D15','I_car_arm_n':'D5',
                  'I_car_stop_n':'A9','I_car_obstacle_n':'B9','I_car_slow_n':'C7'}.items():
    assert any(name in line and re.search(r'\b'+pin+r'\b', line) for line in adc.splitlines()), (name,pin)
sim = json.loads((root/'reports/simulation_summary.json').read_text(encoding='utf-8-sig'))
assert len(sim) == 4 and all(x['Passed'] for x in sim)
video_sim = json.loads((root/'reports/video720_simulation_summary.json').read_text(encoding='utf-8-sig'))
assert len(video_sim) == 6 and all(x['Passed'] for x in video_sim)
stages = (root/'integration/td_bit/stages_all.log').read_text(encoding='utf-8')
assert 'CAR_BIT_BUILD_OK' in stages and 'CAR_BIT_BUILD_FAILED' not in stages
from verify_bit import audit
bit_report = audit(root)
assert bit_report['passed'], 'Current bit generation/timing verification failed'
manifest = json.loads((root/'reports/bit_build_inputs.json').read_text(encoding='utf-8'))
for item in manifest['inputs']:
    assert hashlib.sha256((root/item['path']).read_bytes()).hexdigest() == item['sha256'], item['path']
assert manifest['video']['width'] == 1280 and manifest['video']['height'] == 720
hex_file = root/'stm32/WHEELTEC_C50X_FPGA_PD89/OBJ/cli_4WD/4WD_Car_FPGA_PD89.hex'
hex_hash = hashlib.sha256(hex_file.read_bytes()).hexdigest()
assert hex_hash == '679db582c25c618cd6b3340b74cf67731a9d89854dcdb87797ba412d5449cec8', hex_hash
report = {'passed': True, 'base_commit':'c37b61cc31d9dc6ba8713a95a0caffe067c5c77d',
          'td_input_count':len(paths),'rtl_modules':rtl,'simulations':sim,'video_simulations':video_sim,'bit_status':bit_report['status'],'stm32_hex_sha256':hex_hash}
if '--check-only' not in sys.argv:
    (root/'reports/delivery_check.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print('DELIVERY CHECK PASSED: all TD inputs, 8 modules, 6 pin mappings, 10 simulations, current bit/STA, source hashes and STM32 HEX hash')
