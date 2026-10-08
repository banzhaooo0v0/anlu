param([string]$VivadoBin = 'D:\Xilinx\Vivado\2019.2\bin')
$ErrorActionPreference = 'Stop'
$taskRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workRoot = Join-Path $PSScriptRoot 'work_repro'
$reportRoot = Join-Path $taskRoot 'reports'
New-Item -ItemType Directory -Force -Path $workRoot,$reportRoot | Out-Null
foreach ($exe in @('xvlog.bat','xelab.bat','xsim.bat')) {
    if (-not (Test-Path -LiteralPath (Join-Path $VivadoBin $exe))) {
        throw "Missing $exe; pass -VivadoBin with your Vivado bin directory"
    }
}
$rtlFiles = @(Get-ChildItem -LiteralPath (Join-Path $taskRoot 'rtl') -Filter '*.v' | Sort-Object Name | ForEach-Object { $_.FullName })
$tests = @(
    @{Name='tb_car_uart'; Marker='ALL CAR UART TESTS PASSED'},
    @{Name='tb_car_decision'; Marker='PASS tb_car_decision'},
    @{Name='tb_car_result_cdc'; Marker='PASS tb_car_result_cdc'},
    @{Name='tb_car_control'; Marker='PASS tb_car_control'}
)
$summary = @()
foreach ($test in $tests) {
    $testWork = Join-Path $workRoot $test.Name
    New-Item -ItemType Directory -Force -Path $testWork | Out-Null
    Push-Location -LiteralPath $testWork
    try {
        $testFile = Join-Path $PSScriptRoot ($test.Name + '.sv')
        & (Join-Path $VivadoBin 'xvlog.bat') @rtlFiles --sv $testFile -log 'compile.log' *> 'compile_console.log'
        if ($LASTEXITCODE -ne 0) { throw "xvlog failed: $testWork\compile_console.log" }
        & (Join-Path $VivadoBin 'xelab.bat') $test.Name -s ($test.Name + '_snapshot') -log 'elaborate.log' *> 'elaborate_console.log'
        if ($LASTEXITCODE -ne 0) { throw "xelab failed: $testWork\elaborate_console.log" }
        & (Join-Path $VivadoBin 'xsim.bat') ($test.Name + '_snapshot') -runall -log 'run.log' *> 'run_console.log'
        if ($LASTEXITCODE -ne 0) { throw "xsim failed: $testWork\run_console.log" }
        $runText = Get-Content -LiteralPath 'run.log' -Raw
        if ($runText -notmatch [regex]::Escape($test.Marker) -or $runText -match '(?im)^\s*(Fatal|ERROR)\b') {
            throw "Simulation did not pass self-check: $testWork\run.log"
        }
        Copy-Item -LiteralPath 'run.log' -Destination (Join-Path $reportRoot ($test.Name + '.log')) -Force
        $marker = ($runText -split "`r?`n" | Where-Object { $_ -like ('*' + $test.Marker + '*') }) -join ' '
        $summary += @{ Test=$test.Name; Passed=$true; Marker=$marker }
        Write-Output $marker
    } finally { Pop-Location }
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $reportRoot 'simulation_summary.json') -Encoding UTF8
Write-Output 'ALL FOUR RTL SIMULATIONS PASSED'
