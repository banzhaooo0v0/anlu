param(
    [string]$TdExe = 'E:\Software\TD5.6.2\bin\td_commands_prompt.exe',
    [switch]$Physical,
    [ValidateSet('auto','1','2','4','8')]
    [string]$Threads = '1'
)
$ErrorActionPreference = 'Stop'
$repoDir = Split-Path -Parent $PSScriptRoot
$projectDir = Join-Path $repoDir 'td_project'
$reportDir = Join-Path $repoDir 'reports'
if (!(Test-Path -LiteralPath $TdExe)) { throw "TD executable missing: $TdExe" }
New-Item -ItemType Directory -Force $reportDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$consoleLog = Join-Path $reportDir "td_verify_${stamp}.log"
$runs = @('syn_1')
if ($Physical) { $runs += 'phy_1' }
foreach ($run in $runs) {
    $commands = @(
        'import_device ph1_35p.db -package PH1P35MDG324 -speed 3',
        'open_project camera_to_dsi_display.al -single_run',
        'top_module design_top_wrapper',
        "reset_runs $run -f",
        # TD 6.2.168116 crashed in detailed routing with automatic workers.
        # This controls workers inside the run; launch_runs -jobs is different.
        "set_param flow thread $Threads -run $run"
    )
    if ($run -eq 'phy_1') {
        # Compressed bitgen also crashes on this design in TD 6.2.168116.
        $commands += "set_param bitgen compress off -run $run"
    }
    $commands += @("launch_runs $run -jobs 4", "wait_run $run -quiet", 'exit')
    $phaseLog = Join-Path $reportDir "td_console_${run}_${stamp}.log"
    Push-Location $projectDir
    try {
        ($commands -join "`n") | & $TdExe 2>&1 | Out-File -FilePath $phaseLog -Encoding utf8
        $tdExit = $LASTEXITCODE
    } finally { Pop-Location }
    $text = Get-Content -LiteralPath $phaseLog -Raw
    Add-Content -LiteralPath $consoleLog -Value $text -Encoding utf8
    $runDir = Join-Path $projectDir "camera_to_dsi_display_Runs/$run"
    if (Test-Path (Join-Path $runDir 'run.log')) {
        Copy-Item (Join-Path $runDir 'run.log') (Join-Path $reportDir "td_${run}_${stamp}.log")
    }
    $bat = Join-Path $runDir 'run.bat'
    if (Test-Path -LiteralPath $bat) {
        $batText = Get-Content -LiteralPath $bat -Raw
        $batText.Replace('td_commands_prompt_commands_prompt.exe','td_commands_prompt.exe') |
            Set-Content -LiteralPath $bat -Encoding ascii -NoNewline
    }
    # Child failure may leave the parent exit code zero. Do not launch physical
    # implementation after a failed synthesis, or reuse historical timing files.
    if ($tdExit -ne 0 -or $text -match '(?m)^[A-Z]+-\d+ ERROR:' -or
        $text -notmatch "Run $run success\.") {
        throw "TD $run failed or incomplete. Read $consoleLog"
    }
    $suffix = if ($run -eq 'syn_1') { 'gate' } else { 'pr' }
    $timingFile = Join-Path $runDir "camera_to_dsi_display_${suffix}.timing"
    Copy-Item $timingFile (Join-Path $reportDir "td_${suffix}_${stamp}.timing")
    $areaSuffix = if ($run -eq 'syn_1') { 'gate' } else { 'phy' }
    $areaFile = Join-Path $runDir "camera_to_dsi_display_${areaSuffix}.area"
    if (Test-Path $areaFile) { Copy-Item $areaFile (Join-Path $reportDir "td_${areaSuffix}_${stamp}.area") }
    # Estimated synthesis timing is diagnostic when a routed result follows.
    $timing = Get-Content -LiteralPath $timingFile -Raw
    foreach ($kind in @('SWNS', 'HWNS')) {
        $match = [regex]::Match($timing, ($kind + ':\s*(-?\d+(?:\.\d+)?)ns'))
        if (!$match.Success) { throw "Missing $kind in $timingFile" }
        if ([double]::Parse($match.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0) {
            if ($run -eq 'syn_1' -and $Physical) { Write-Warning "Estimated $kind negative; routed timing still required" }
            else { throw "Negative $kind in $timingFile" }
        }
    }
}
Write-Output "TD flow and constrained timing PASS. Log: $consoleLog"
