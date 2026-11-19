#Requires -Version 5.1
# Night run (00:00): execute all BatchRun*.ffs_batch sequentially,
# write report JSON for the morning Pachca sender (09:00).
# Does NOT send to Pachca.

$ErrorActionPreference = 'Stop'

# --- configure ---
$BatchDir     = Join-Path $env:USERPROFILE 'Documents'
$FreeFileSync = 'C:\Program Files\FreeFileSync\FreeFileSync.exe'
$LogDir       = Join-Path $env:USERPROFILE 'Documents\BackupBatchLogs'
$Filter       = 'BatchRun*.ffs_batch'
$TimeoutSec   = 6 * 60 * 60
$ReportPath   = Join-Path $LogDir 'last-backup-report.json'
# --- end configure ---

if (-not (Test-Path -LiteralPath $FreeFileSync)) { throw "FreeFileSync not found: $FreeFileSync" }
if (-not (Test-Path -LiteralPath $BatchDir)) { throw "Batch folder not found: $BatchDir" }
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$runLog = Join-Path $LogDir ("run_{0}.log" -f $stamp)
$startedAt = Get-Date
$jobs = New-Object System.Collections.Generic.List[object]

function Write-Log([string]$Message) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $runLog -Value $line -Encoding UTF8
    Write-Host $line
}

function Get-UserFromBatchName([string]$BaseName) {
    # BatchRunPotapov -> Potapov
    if ($BaseName -match '^BatchRun(.+)$') { return $Matches[1] }
    return $BaseName
}

function Test-IsBenignSourceError([string]$Text) {
    if (-not $Text) { return $true }
    # Expected on read-only source shares (user PC)
    if ($Text -match 'sync\.ffs_lock') { return $true }
    if ($Text -match 'sync\.ffs_db') { return $true }
    if ($Text -match '(?i)block|блокиров') { return $true }
    if ($Text -match 'ERROR_ACCESS_DENIED' -and $Text -match 'sync\.ffs_') { return $true }
    return $false
}

function Get-RecentErrorLines([datetime]$Since) {
    $lines = New-Object System.Collections.Generic.List[string]
    $files = @()
    $files += Get-ChildItem -LiteralPath $LogDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since.AddMinutes(-1) }
    $files += Get-ChildItem -LiteralPath $BatchDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since.AddMinutes(-1) -and $_.Extension -match '\.(log|html|txt)$' }

    foreach ($f in ($files | Sort-Object FullName -Unique)) {
        try {
            $content = Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
            if (-not $content) {
                $content = Get-Content -LiteralPath $f.FullName -Encoding Default -ErrorAction SilentlyContinue
            }
            foreach ($line in $content) {
                if ($line -match '(?i)error|ошибк|внимание|warning|невозможно') {
                    $lines.Add(('{0} | {1}' -f $f.Name, $line.Trim())) | Out-Null
                }
            }
        } catch { }
    }
    return $lines
}

Write-Log ("START batch folder: {0}" -f $BatchDir)

$batches = @(Get-ChildItem -LiteralPath $BatchDir -Filter $Filter -File | Sort-Object Name)
if ($batches.Count -eq 0) {
    Write-Log ("No files matching {0}" -f $Filter)
}

foreach ($b in $batches) {
    $user = Get-UserFromBatchName $b.BaseName
    Write-Log ("RUN  {0} (user {1})" -f $b.FullName, $user)
    $jobStart = Get-Date

    $p = Start-Process -FilePath $FreeFileSync `
        -ArgumentList("`"{0}`"" -f $b.FullName) `
        -PassThru -WindowStyle Hidden

    $exited = $true
    try { Wait-Process -Id $p.Id -Timeout $TimeoutSec -ErrorAction Stop }
    catch { $exited = $false }

    $rawErrors = New-Object System.Collections.Generic.List[string]
    $status = 'OK'
    $exitCode = -1

    if (-not $exited -or -not $p.HasExited) {
        Write-Log ("TIMEOUT {0}" -f $b.Name)
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        Get-Process -Name 'FreeFileSync*','ffs_*' -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        $status = 'FAIL'
        $rawErrors.Add('TIMEOUT waiting for FreeFileSync') | Out-Null
    } else {
        $p.Refresh()
        $exitCode = $p.ExitCode
        $recent = Get-RecentErrorLines -Since $jobStart
        foreach ($e in $recent) { $rawErrors.Add($e) | Out-Null }

        $realErrors = @($rawErrors | Where-Object { -not (Test-IsBenignSourceError $_) })

        if ($exitCode -eq 0 -and $realErrors.Count -eq 0) {
            $status = 'OK'
            Write-Log ("OK   {0} exit={1}" -f $b.Name, $exitCode)
        } elseif ($realErrors.Count -eq 0) {
            # Only benign source-lock warnings (typical exit 1)
            $status = 'OK'
            Write-Log ("OK   {0} exit={1} (only benign source-lock warnings)" -f $b.Name, $exitCode)
        } else {
            $status = 'FAIL'
            Write-Log ("FAIL {0} exit={1} realErrors={2}" -f $b.Name, $exitCode, $realErrors.Count)
        }
    }

    $sec = [int]((Get-Date) - $jobStart).TotalSeconds
    $jobs.Add([pscustomobject]@{
        User          = $user
        Batch         = $b.Name
        Status        = $status
        ExitCode      = $exitCode
        DurationSec   = $sec
        StartedLocal  = $jobStart.ToString('yyyy-MM-dd HH:mm:ss')
        FinishedLocal = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Errors        = @($rawErrors | Where-Object { -not (Test-IsBenignSourceError $_) })
        IgnoredNoise  = @($rawErrors | Where-Object { Test-IsBenignSourceError $_ })
    }) | Out-Null
}

$finishedAt = Get-Date
$failCount = @($jobs | Where-Object { $_.Status -ne 'OK' }).Count

$report = [pscustomobject]@{
    Server        = $env:COMPUTERNAME
    RunDate       = $startedAt.ToString('yyyy-MM-dd')
    StartedLocal  = $startedAt.ToString('yyyy-MM-dd HH:mm:ss')
    FinishedLocal = $finishedAt.ToString('yyyy-MM-dd HH:mm:ss')
    DurationSec   = [int]($finishedAt - $startedAt).TotalSeconds
    JobsTotal     = $jobs.Count
    JobsFailed    = $failCount
    RunLog        = $runLog
    Jobs          = $jobs
}

$json = $report | ConvertTo-Json -Depth 6
Set-Content -LiteralPath $ReportPath -Value $json -Encoding UTF8
$datedReport = Join-Path $LogDir ("backup-report_{0}.json" -f $startedAt.ToString('yyyy-MM-dd'))
Set-Content -LiteralPath $datedReport -Value $json -Encoding UTF8

Write-Log ("REPORT {0}" -f $ReportPath)
Write-Log ("DONE jobs={0} failed={1}" -f $jobs.Count, $failCount)
Write-Log 'EXIT'

if ($failCount -gt 0) { exit 1 } else { exit 0 }
