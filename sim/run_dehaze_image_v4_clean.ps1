param(
    [string]$InputImage = 'E:\FPGA\workspace\Fog.png',
    [string]$OutputDir = '',
    [string]$VivadoBin = 'E:\Software\Vivado\Vivado\2019.2\bin'
)
$ErrorActionPreference = 'Stop'
$repoDir = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $PSScriptRoot ('build_fog_v4_' + [IO.Path]::GetFileNameWithoutExtension($InputImage))
if (!$OutputDir) { $OutputDir = Join-Path $buildDir 'preview' }
$InputImage = (Resolve-Path -LiteralPath $InputImage).Path
$OutputDir = [IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Force $buildDir, $OutputDir | Out-Null
python (Join-Path $PSScriptRoot 'run_dehaze_image.py') prepare --input $InputImage --build $buildDir --output $OutputDir
if ($LASTEXITCODE -ne 0) { throw 'Image preparation failed' }
Push-Location $buildDir
try {
    & "$VivadoBin/xvlog.bat" --sv '../../user_source/hdl_source/ip/image/dehaze_stream_96.v' '../tb_dehaze_image.sv'
    if ($LASTEXITCODE -ne 0) { throw 'Image RTL compilation failed' }
    & "$VivadoBin/xelab.bat" tb_dehaze_image -s fog_image_test -R
    $exitCode = $LASTEXITCODE
    $log = Get-Content xsim.log -Raw
    Copy-Item xsim.log (Join-Path $OutputDir 'xsim.log')
    if ($exitCode -ne 0 -or $log -notmatch 'PASS: image RTL' -or $log -match 'Fatal:|ERROR:') {
        throw 'Image RTL simulation failed'
    }
} finally { Pop-Location }
python (Join-Path $PSScriptRoot 'run_dehaze_image.py') collect --input $InputImage --build $buildDir --output $OutputDir
if ($LASTEXITCODE -ne 0) { throw 'Image output verification failed' }
