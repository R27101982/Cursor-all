#Requires -Version 5.1
# Night run (00:00): execute ALL BatchRun*.ffs_batch in Documents, one by one.
# Writes last-backup-report.json for morning Pachca report. Does NOT send to Pachca.

$ErrorActionPreference = 'Stop'

# --- configure ---
$BatchDir     = Join-Path $env:USERPROFILE 'Documents'
$FreeFileSync = 'C:\Program Files\FreeFileSync\FreeFileSync.exe'
$LogDir       = Join-Path $env:USERPROFILE 'Documents\BackupBatchLogs'
$TimeoutSec   = 6 * 60 * 60
$ReportPath   = Join-Path $LogDir 'last-backup-report.json'
$GapSec       = 3   # pause between batches so FreeFileSync fully exits
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

function Stop-FreeFileSync {
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -like 'FreeFileSync*' -or $_.ProcessName -like 'ffs_*' } |
        ForEach-Object {
            try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch { }
        }
    Start-Sleep -Seconds 1
}

function Get-UserFromBatchName([string]$BaseName) {
    if ($BaseName -match '(?i)^BatchRun(.+)$') { return $Matches[1] }
    return $BaseName
}

function Test-IsBenignSourceError([string]$Text) {
    if (-not $Text) { return $true }
    if ($Text -match 'sync\.ffs_lock') { return $true }
    if ($Text -match 'sync\.ffs_db') { return $true }
    if ($Text -match '(?i)block') { return $true }
    if ($Text -match 'ERROR_ACCESS_DENIED' -and $Text -match 'sync\.ffs_') { return $true }
    return $false
}

function Get-RecentErrorLines([datetime]$Since) {
    $lines = New-Object System.Collections.Generic.List[string]
    $files = @()
    $files += @(Get-ChildItem -LiteralPath $LogDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since.AddMinutes(-1) })
    $files += @(Get-ChildItem -LiteralPath $BatchDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since.AddMinutes(-1) -and $_.Extension -match '\.(log|html|txt)$' })

    $ruErr = -join ([char[]]@(0x043E,0x0448,0x0438,0x0431))
    $ruAtt = -join ([char[]]@(0x0412,0x043D,0x0438,0x043C,0x0430))
    $ruImp = -join ([char[]]@(0x043D,0x0435,0x0432,0x043E,0x0437))

    foreach ($f in ($files | Sort-Object FullName -Unique)) {
        try {
            $content = Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
            if (-not $content) {
                $content = Get-Content -LiteralPath $f.FullName -Encoding Default -ErrorAction SilentlyContinue
            }
            foreach ($line in $content) {
                if ($line -match '(?i)error|warning|access_denied' -or $line -match $ruErr -or $line -match $ruAtt -or $line -match $ruImp) {
                    $lines.Add(('{0} | {1}' -f $f.Name, $line.Trim())) | Out-Null
                }
            }
        } catch { }
    }
    return ,$lines.ToArray()
}

Write-Log ("START batch folder: {0}" -f $BatchDir)

# List ALL .ffs_batch, then keep BatchRun* (case-insensitive). More reliable than -Filter alone.
$allBatch = @(Get-ChildItem -LiteralPath $BatchDir -File -ErrorAction Stop |
    Where-Object { $_.Extension -match '^\.ffs_batch$' })
$batches = @($allBatch | Where-Object { $_.BaseName -like 'BatchRun*' } | Sort-Object Name)

Write-Log ("Found .ffs_batch total: {0}" -f $allBatch.Count)
if ($allBatch.Count -gt 0) {
    Write-Log ("All batch files: {0}" -f (($allBatch | ForEach-Object { $_.Name }) -join ', '))
}
Write-Log ("Queue ({0}): {1}" -f $batches.Count, (($batches | ForEach-Object { $_.Name }) -join ', '))

if ($batches.Count -eq 0) {
    Write-Log 'No BatchRun*.ffs_batch files to run'
}

$index = 0
foreach ($b in $batches) {
    $index++
    $user = Get-UserFromBatchName $b.BaseName
    Write-Log ("RUN [{0}/{1}] {2} (user {3})" -f $index, $batches.Count, $b.FullName, $user)
    $jobStart = Get-Date

    $rawErrors = New-Object System.Collections.Generic.List[string]
    $status = 'OK'
    $exitCode = -1

    try {
        # Ensure previous FreeFileSync instance is gone (single-instance app)
        Stop-FreeFileSync
        Start-Sleep -Seconds $GapSec

        $p = Start-Process -FilePath $FreeFileSync `
            -ArgumentList $b.FullName `
            -PassThru `
            -WindowStyle Hidden

        if (-not $p) {
            throw 'Start-Process returned null'
        }

        Write-Log ("     started PID {0}" -f $p.Id)

        $exited = $true
        try {
            Wait-Process -Id $p.Id -Timeout $TimeoutSec -ErrorAction Stop
        } catch {
            $exited = $false
        }

        if (-not $exited) {
            try { $p.Refresh() } catch { }
        }

        if (-not $exited -or -not $p.HasExited) {
            Write-Log ("TIMEOUT {0}" -f $b.Name)
            Stop-FreeFileSync
            $status = 'FAIL'
            $rawErrors.Add('TIMEOUT waiting for FreeFileSync') | Out-Null
        } else {
            try { $p.Refresh() } catch { }
            try { $exitCode = $p.ExitCode } catch { $exitCode = -1 }

            $recent = @(Get-RecentErrorLines -Since $jobStart)
            foreach ($e in $recent) { $rawErrors.Add($e) | Out-Null }

            $realErrors = @($rawErrors | Where-Object { -not (Test-IsBenignSourceError $_) })

            if ($realErrors.Count -eq 0) {
                $status = 'OK'
                Write-Log ("OK   {0} exit={1}" -f $b.Name, $exitCode)
            } else {
                $status = 'FAIL'
                Write-Log ("FAIL {0} exit={1} realErrors={2}" -f $b.Name, $exitCode, $realErrors.Count)
            }
        }
    } catch {
        $status = 'FAIL'
        $msg = $_.Exception.Message
        $rawErrors.Add($msg) | Out-Null
        Write-Log ("ERROR {0}: {1}" -f $b.Name, $msg)
        Stop-FreeFileSync
    }

    # Always clear FFS before next batch
    Stop-FreeFileSync
    Start-Sleep -Seconds $GapSec

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
    Jobs          = @($jobs)
}

$json = $report | ConvertTo-Json -Depth 8
Set-Content -LiteralPath $ReportPath -Value $json -Encoding UTF8
$datedReport = Join-Path $LogDir ("backup-report_{0}.json" -f $startedAt.ToString('yyyy-MM-dd'))
Set-Content -LiteralPath $datedReport -Value $json -Encoding UTF8

Write-Log ("REPORT {0}" -f $ReportPath)
Write-Log ("DONE jobs={0} failed={1}" -f $jobs.Count, $failCount)
Write-Log 'EXIT'

if ($failCount -gt 0) { exit 1 } else { exit 0 }
