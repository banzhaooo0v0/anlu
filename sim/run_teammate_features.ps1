param(
  [string]$VivadoBin = 'E:\Software\Vivado\Vivado\2019.2\bin',
  [string]$Test = '*'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $PSScriptRoot 'build_teammate_features'
$report = Join-Path $root 'reports'
New-Item -ItemType Directory -Force $work,$report | Out-Null
$rtl = @(Get-ChildItem (Join-Path $root 'user_source/hdl_source/ip/car') -Filter '*.v' | Sort-Object Name | ForEach-Object FullName)
$rtl += Join-Path $root 'user_source/hdl_source/ip/image/traffic_sign/traffic_sign_detector_96.v'
$rtl += Join-Path $root 'user_source/hdl_source/ip/control/mode_selector.v'
$rtl += Join-Path $root 'user_source/hdl_source/ip/video/osd/osd_char_lib.v'
$rtl += Join-Path $root 'user_source/hdl_source/ip/image/image_process_stream_96.v'
$rtl += Join-Path $root 'user_source/hdl_source/ip/video/osd/hdmi_mixer.v'
$rtl += Join-Path $root 'user_source/hdl_source/ip/video/osd/anlogic_logo_rom.v'
$rtl += Join-Path $root 'user_source/hdl_source/ip/video/vtc/uivtc.v'
$rtl += Join-Path $root 'user_source/hdl_source/ip/image/cnn/cnn_input_sampler_96.v'
$rtl += Join-Path $root 'user_source/hdl_source/ip/image/cnn/cnn_input_bram.v'
$rtl += Join-Path $root 'user_source/hdl_source/ip/camera/config/uiisp_beta/sc500_auto_exposure.v'
$rtl += Join-Path $root 'user_source/hdl_source/ip/camera/config/uics500_cfg/SC500GainTbl.v'
$rtl += Join-Path $root 'sim/models/demosaic_ram_behavioral.v'
$rtl += Join-Path $root 'sim/fixtures/line_buffer_demosaic_baseline.v'
$rtl += Join-Path $root 'sim/fixtures/zhenghe_baseline.v'
$rtl += Join-Path $root 'user_source/hdl_source/ip/image/demosaic_4x_2_0/line_buffer_demosaic.v'
$rtl += Join-Path $root 'user_source/hdl_source/ip/image/demosaic_4x_2_0/zhenghe.v'
$rtl += Join-Path $root 'user_source/hdl_source/ip/image/demosaic_4x_2_0/blk_mem_gen_demosaic/blk_mem_gen_demosaic.v'
$rtl += Join-Path $root 'user_source/hdl_source/ip/image/demosaic_4x_2_0/blk_mem_gen_zhenghe/blk_mem_gen_zhenghe.v'
$rtl += Join-Path $root 'user_source/hdl_source/ip/camera/mipi/uial2axis.v'
$tests = @(
  @{Name='tb_demosaic_ram_resize'; Marker='PASS demosaic RAM'},
  @{Name='tb_native_720p'; Marker='PASS native 720p'},
  @{Name='tb_cnn_handshake_720p'; Marker='CNN INPUT SAMPLER DOUBLE BUFFER TEST PASSED'},
  @{Name='tb_hdmi_720p'; Marker='PASS HDMI 1280x720'},
  @{Name='tb_cnn_sampler_720p'; Marker='CNN INPUT SAMPLER TEST PASSED'},
  @{Name='tb_sc500_auto_exposure'; Marker='BRIGHT_OK'},
  @{Name='tb_sc500_gain_table'; Marker='GAIN_TABLE_OK'},
  @{Name='tb_pixel_morphology'; Marker='PASS pixel morphology'},
  @{Name='tb_board_mode_selector'; Marker='PASS BOARD KEY4 MODE SELECTOR'},
  @{Name='tb_osd_question'; Marker='PASS OSD QUESTION GLYPH'},
  @{Name='tb_car_uart'; Marker='ALL CAR UART TESTS PASSED'},
  @{Name='tb_car_decision'; Marker='PASS tb_car_decision'},
  @{Name='tb_car_result_cdc'; Marker='PASS tb_car_result_cdc'},
  @{Name='tb_car_control'; Marker='PASS tb_car_control'},
  @{Name='tb_traffic_sign_detector_96'; Marker='PASS traffic sign detector'}
)
$selected = @($tests | Where-Object { $_.Name -like $Test })
if (!$selected.Count) { throw "No test matches: $Test" }
foreach($case in $selected) {
  $dir = Join-Path $work $case.Name
  New-Item -ItemType Directory -Force $dir | Out-Null
  if ($case.Name -eq 'tb_pixel_morphology') {
    python (Join-Path $PSScriptRoot 'generate_morph_vectors.py') --out $dir
    if ($LASTEXITCODE -ne 0) { throw 'Morphology reference generation failed' }
  }
  Push-Location $dir
  try {
    & (Join-Path $VivadoBin 'xvlog.bat') @rtl --sv -d CNN_SIM (Join-Path $PSScriptRoot "teammate_features/$($case.Name).sv") -log compile.log *> compile_console.log
    if($LASTEXITCODE -ne 0){ throw "compile failed: $($case.Name)" }
    $elabOptions = @()
    if ($case.Name -in @('tb_demosaic_ram_resize','tb_native_720p')) { $elabOptions = @('--O0','--mt','off') }
    & (Join-Path $VivadoBin 'xelab.bat') @elabOptions $case.Name -s "$($case.Name)_snapshot" -log elaborate.log *> elaborate_console.log
    if($LASTEXITCODE -ne 0){ throw "elaborate failed: $($case.Name)" }
    & (Join-Path $VivadoBin 'xsim.bat') "$($case.Name)_snapshot" -runall -log run.log *> run_console.log
    if($LASTEXITCODE -ne 0){ throw "simulation failed: $($case.Name)" }
    $text = Get-Content run.log -Raw
    Copy-Item run.log (Join-Path $report "$($case.Name)_20261009.log") -Force
    if($text -notmatch [regex]::Escape($case.Marker) -or $text -match '(?im)^\s*(Fatal|ERROR)\b'){ throw "self-check failed: $($case.Name)" }
    Write-Output (($text -split "`r?`n" | Where-Object {$_ -like "*$($case.Marker)*"}) -join ' ')
  } finally { Pop-Location }
}
Write-Output "SELECTED FEATURE SIMULATIONS PASSED: $Test"
