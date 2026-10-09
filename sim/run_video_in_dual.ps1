param([string]$VivadoBin = 'E:\Software\Vivado\Vivado\2019.2\bin')
$ErrorActionPreference = 'Stop'
$repoDir = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $PSScriptRoot 'build_dual'
New-Item -ItemType Directory -Force $buildDir | Out-Null
Push-Location $buildDir
try {
    & "$VivadoBin/xvlog.bat" --sv `
        '../../user_source/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v' `
        '../../user_source/ip_source/w128_d512_fifo/w128_d512_fifo.v' `
        '../../user_source/hdl_source/ip/video/video_in_dual.v' '../tb_video_in_dual.sv'
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    & "$VivadoBin/xelab.bat" tb_video_in_dual -s dual_test -R
    if ($LASTEXITCODE -ne 0) { throw 'xelab/xsim failed' }
    $log = Get-Content xsim.log -Raw
    if ($log -notmatch 'PASS: dual FIFO RTL' -or $log -match 'Fatal:|Error:') {
        throw 'Dual FIFO scoreboard did not pass; read sim/build_dual/xsim.log'
    }
    Copy-Item xsim.log (Join-Path $repoDir 'reports/rtl_video_in_dual_20261008.log')
} finally { Pop-Location }
