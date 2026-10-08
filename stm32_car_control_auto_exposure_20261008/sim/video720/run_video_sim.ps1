param([string]$VivadoBin='D:\Xilinx\Vivado\2019.2\bin', [string[]]$Only=@())
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$source=Join-Path $taskRoot 'fpga\traffic_sign_td\user_source'
$hdl=Join-Path $source 'lab_ex_2026_nosoft\hdl_source'
$tests=@(
 @{Name='tb_board_mode_selector';Files=@("$hdl\mode_selector.v");Marker='PASS BOARD KEY4 MODE SELECTOR'},
 @{Name='tb_osd_question';Files=@("$hdl\osd_char_lib.v");Marker='PASS OSD QUESTION GLYPH'},
 @{Name='tb_image_process_stream_96_full';Files=@("$source\image\stream\image_process_stream_96.v");Marker='FULL FRAME STREAM TEST PASSED'},
 @{Name='tb_traffic_sign_detector_96';Files=@("$source\image\traffic_sign\traffic_sign_detector_96.v");Marker='PASS traffic sign detector'},
 @{Name='tb_hdmi_720p';Files=@("$hdl\vtc\uivtc.v","$hdl\hdmi_mixer.v","$hdl\anlogic_logo_rom.v","$hdl\osd_char_lib.v");Marker='PASS HDMI 1280x720'},
 @{Name='tb_hdmi_black_camera';Files=@("$hdl\vtc\uivtc.v","$hdl\hdmi_mixer.v","$hdl\anlogic_logo_rom.v","$hdl\osd_char_lib.v");Marker='PASS HDMI BLACK CAMERA'}
)
$summary=@()
foreach($test in $tests){
 if($Only.Count -gt 0 -and $test.Name -notin $Only){
  $previous=Get-Content -LiteralPath (Join-Path $taskRoot ('reports\'+$test.Name+'_720p.log')) -Raw
  if($previous -notmatch [regex]::Escape($test.Marker)){throw "Missing previous passing result: $($test.Name)"}
  $summary+=@{Test=$test.Name;Passed=$true;Marker=$test.Marker}
  continue
 }
 $taskWork=Join-Path $PSScriptRoot ('work\'+$test.Name)
 New-Item -ItemType Directory -Force -Path $taskWork | Out-Null
 Push-Location -LiteralPath $taskWork
 try{
  $sources=$test.Files
  & "$VivadoBin\xvlog.bat" @sources --sv (Join-Path $PSScriptRoot ($test.Name+'.sv')) -log compile.log *> compile_console.log
  if($LASTEXITCODE -ne 0){throw "Compile failed: $taskWork"}
  & "$VivadoBin\xelab.bat" $test.Name -s snapshot -log elaborate.log *> elaborate_console.log
  if($LASTEXITCODE -ne 0){throw "Elaboration failed: $taskWork"}
  & "$VivadoBin\xsim.bat" snapshot -runall -log run.log *> run_console.log
  $taskText=Get-Content -LiteralPath run.log -Raw
  if($LASTEXITCODE -ne 0 -or $taskText -notmatch [regex]::Escape($test.Marker) -or $taskText -match '(?im)^\s*(Fatal|ERROR|\[FAIL\]|FAIL)\b'){throw "Simulation failed: $taskWork"}
  Copy-Item -LiteralPath run.log -Destination (Join-Path $taskRoot ('reports\'+$test.Name+'_720p.log')) -Force
  $summary+=@{Test=$test.Name;Passed=$true;Marker=$test.Marker}
  Write-Output $test.Marker
 }finally{Pop-Location}
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskRoot 'reports\video720_simulation_summary.json') -Encoding utf8
Write-Output 'ALL VIDEO SIMULATIONS PASSED'
