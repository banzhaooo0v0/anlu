"""Check the active camera/ISP/HDMI 720P profile and frozen build inputs."""
from pathlib import Path
import hashlib
import json
import re

root = Path(__file__).resolve().parents[1]
src = root / 'fpga/traffic_sign_td/user_source'
hdl = src / 'lab_ex_2026_nosoft/hdl_source'
top = (hdl/'design_top_wrapper.v').read_text(encoding='utf-8-sig')
assert re.search(r'VIDEO_WIDTH\s*=\s*1280\s*;', top)
assert re.search(r'VIDEO_HEIGHT\s*=\s*720\s*;', top)
for name, value in {'H_ActiveSize':'VIDEO_WIDTH','V_ActiveSize':'VIDEO_HEIGHT',
                    'H_FrameSize':'1650','H_SyncStart':'1390','H_SyncEnd':'1430',
                    'V_FrameSize':'750','V_SyncStart':'725','V_SyncEnd':'730',
                    'H_OFFSET':'0','V_OFFSET':'0'}.items():
    assert re.search(r'\.'+name+r'\s*\(\s*'+value+r'\s*\)',top), name
for signal in ['tdata','tvalid','tlast','tuser']:
    assert re.search(r'assign\s+S_raw_'+signal+r'\s*=\s*S_axis_'+signal+r'\s*;',top), signal
assert not re.search(r'\bimage_correction\s+(?:#|\w+\s*\()',top)
for module in ['uial2axis','isp_top']:
    assert re.search(module+r'\s*#\(\s*\.IMG_WIDTH\(VIDEO_WIDTH\),\s*\.IMG_HEIGHT\(VIDEO_HEIGHT\)',top), module
isp=(src/'image/integration/isp_top.v').read_text(encoding='utf-8-sig')
assert len(re.findall(r'\.IMG_WIDTH\s*\(\s*IMG_WIDTH\s*\)',isp))==4
assert len(re.findall(r'\.IMG_HEIGHT\s*\(\s*IMG_HEIGHT\s*\)',isp))==4
reg_text=(hdl/'uics500_cfg/uics500reg.v').read_text(encoding='utf-8-sig')
registers={int(a,16):int(v,16) for a,v in re.findall(r"\{16'h([0-9a-fA-F]+),8'h([0-9a-fA-F]+)\}",reg_text)}
sensor_width=registers[0x3208]*256+registers[0x3209]
sensor_height=registers[0x320a]*256+registers[0x320b]
assert (sensor_width,sensor_height)==(1280,720)
pll=(src/'ip_source/PLL/PLL.v').read_text(encoding='utf-8-sig')
for name,value in {'REFCLK_DIV':1,'FBCLK_DIV':2,'CLKC0_DIV':15,'CLKC1_DIV':63,'CLKC4_DIV':20,'CLKC5_DIV':4}.items():
    assert re.search(r'\.'+name+r'\('+str(value)+r'\)',pll),name
sdc=(root/'fpga/traffic_sign_td/td_project/traffic_sign_td.sdc').read_text(encoding='utf-8-sig')
assert '-period 4.167 -waveform {0.000 2.083}' in sdc
# The TX core generates its own timing/metadata; matching the external VTC
# alone is insufficient. Inspect only the active instance, not commented demos.
tx=(hdl/'hdmi_tx.v').read_text(encoding='utf-8-sig')
tx=re.sub(r'/\*.*?\*/|//[^\n]*', '', tx, flags=re.S)
tx=tx.split('hdmi_1_4b_transmitter_core_wrapper#(',1)[1].split(')u_hdmi_1_4b_transmitter_core_wrapper',1)[0]
tx_values={k:int(v) for k,v in re.findall(r'\.(\w+)\s*\(\s*(\d+)\s*\)',tx)}
expected_tx={'HTOTAL':1650,'HACTIVE':1280,'HSA':40,'HFP':110,'HBP':220,
             'VTOTAL':750,'VACTIVE':720,'VSA':5,'VFP':5,'VBP':20,'VIDEO_VIC':4}
for name,value in expected_tx.items():
    assert tx_values.get(name)==value, f'HDMI TX mismatch: {name}={tx_values.get(name)}, expected {value}'
assert tx_values['HTOTAL']==sum(tx_values[k] for k in ['HACTIVE','HSA','HFP','HBP'])
assert tx_values['VTOTAL']==sum(tx_values[k] for k in ['VACTIVE','VSA','VFP','VBP'])
manifest=json.loads((root/'reports/bit_build_inputs.json').read_text(encoding='utf-8'))
for item in manifest['inputs']:
    assert hashlib.sha256((root/item['path']).read_bytes()).hexdigest()==item['sha256'],item['path']
print(f'PASS 720P profile: sensor {sensor_width}x{sensor_height}; ISP dimensions; direct frame markers; VTC and HDMI TX 1650x750 / VIC4; PLL 75/375MHz; MIPI clock constraint; {len(manifest["inputs"])} source hashes.')
