param(
    [string]$VivadoBin = 'E:\Software\Vivado\Vivado\2019.2\bin',
    [string]$ReportTag = (Get-Date -Format 'yyyyMMdd')
)
$ErrorActionPreference = 'Stop'
$repoDir = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $PSScriptRoot 'build_dual'
New-Item -ItemType Directory -Force $buildDir | Out-Null
python (Join-Path $PSScriptRoot 'generate_dehaze_vectors.py')
if ($LASTEXITCODE -ne 0) { throw 'Reference generation failed' }
Copy-Item (Join-Path $PSScriptRoot 'fixtures/signal_delay_baseline.v') (Join-Path $buildDir 'signal_delay_baseline.v')
Push-Location $buildDir
try {
    & "$VivadoBin/xvlog.bat" --sv '../../user_source/hdl_source/ip/image/dehaze_stream_96.v' '../tb_dehaze_pipeline.sv'
    if ($LASTEXITCODE -ne 0) { throw 'Dehaze compile failed' }
    & "$VivadoBin/xelab.bat" tb_dehaze_pipeline -s dehaze_test -R
    $log = Get-Content xsim.log -Raw
    if ($LASTEXITCODE -ne 0 -or $log -notmatch 'PASS: dehaze pipeline' -or $log -match 'Fatal:') { throw 'Dehaze simulation failed' }
    Copy-Item xsim.log "../../reports/rtl_dehaze_pipeline_$ReportTag.log"

    # Vendor primitive is encrypted without an XSim key. This test explicitly
    # checks address/depth equivalence using the portable memory contract only.
    & "$VivadoBin/xvlog.bat" --sv '../models/awb_ram_behavioral.v' `
        '../../user_source/ip_source/blk_mem_gen_awb_delay_signal/blk_mem_gen_awb_delay_signal.v' `
        '../../user_source/hdl_source/ip/image/signal_delay.v' 'signal_delay_baseline.v' '../tb_awb_delay_resize.sv'
    if ($LASTEXITCODE -ne 0) { throw 'AWB equivalence compile failed' }
    & "$VivadoBin/xelab.bat" tb_awb_delay_resize -s awb_test -R
    $log = Get-Content xsim.log -Raw
    if ($LASTEXITCODE -ne 0 -or $log -notmatch 'width=1024 groups=1536' -or
        $log -notmatch 'width=1280 groups=1920' -or $log -notmatch 'width=1920 groups=2880' -or $log -match 'Fatal:') { throw 'AWB equivalence failed' }
    Copy-Item xsim.log "../../reports/rtl_awb_resize_$ReportTag.log"
} finally { Pop-Location }
