param([string]$VivadoBin = 'E:\Software\Vivado\Vivado\2019.2\bin')
$ErrorActionPreference = 'Stop'
$buildDir = Join-Path $PSScriptRoot 'build_dual'
New-Item -ItemType Directory -Force $buildDir | Out-Null
Push-Location $buildDir
try {
    & "$VivadoBin/xvlog.bat" --sv `
        '../../user_source/hdl_source/ip/image/dehaze_stream_96.v' `
        '../../user_source/hdl_source/ip/image/image_process_stream_96.v' `
        '../../user_source/hdl_source/ip/image/data96_128/data96_128.v' `
        '../../user_source/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v' `
        '../../user_source/ip_source/w128_d512_fifo/w128_d512_fifo.v' `
        '../../user_source/hdl_source/ip/video/video_in_dual.v' '../tb_member2_integration.sv'
    if ($LASTEXITCODE -ne 0) { throw 'Integration compile failed' }
    & "$VivadoBin/xelab.bat" tb_member2_integration -s member2_test -R
    $log = Get-Content xsim.log -Raw
    if ($LASTEXITCODE -ne 0 -or $log -notmatch 'PASS: integrated member2 path' -or $log -match 'Fatal:') {
        throw 'Integration scoreboard did not pass'
    }
    Copy-Item xsim.log '../../reports/rtl_member2_integration_20261009.log'
} finally { Pop-Location }

