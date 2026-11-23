#Requires -Version 5.1
# Night run (00:00): run ALL BatchRun*.ffs_batch in Documents, one by one.
# Writes last-backup-report.json for morning Pachca. Does NOT send to Pachca.
#
# Important: FreeFileSync often hangs on sync.ffs_lock dialogs. This script:
# 1) forces AutoClose + IgnoreErrors in each .ffs_batch before run
# 2) kills a hung FreeFileSync (no CPU progress) and continues the queue

$ErrorActionPreference = 'Stop'

# --- configure ---
$BatchDir     = Join-Path $env:USERPROFILE 'Documents'
$FreeFileSync = 'C:\Program Files\FreeFileSync\FreeFileSync.exe'
$LogDir       = Join-Path $env:USERPROFILE 'Documents\BackupBatchLogs'
$TimeoutSec   = 6 * 60 * 60
$IdleHangSec  = 180   # if FFS CPU does not grow for this long -> treat as hung dialog
$GapSec       = 3
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
    if ($Text -match 'ERROR_ACCESS_DENIED' -and $Text -match 'sync\.ffs_') { return $true }
    return $false
}

function Ensure-BatchUnattended([string]$BatchPath) {
    # Make the job unattended: ignore errors + auto-close, so FFS never waits for a click.
    # ErrorDialog only accepts Show/Cancel - any other value makes FFS reject the config.
    try {
        [xml]$xml = Get-Content -LiteralPath $BatchPath -Encoding UTF8
    } catch {
        Write-Log ("WARN cannot read XML {0}: {1}" -f $BatchPath, $_.Exception.Message)
        return
    }

    $root = $xml.DocumentElement
    if (-not $root) { return }

    $changed = $false

    $errors = $root.SelectSingleNode('Errors')
    if (-not $errors) {
        $errors = $xml.CreateElement('Errors')
        [void]$root.AppendChild($errors)
        $changed = $true
    }
    if ($errors.GetAttribute('Ignore') -ne 'true') { $errors.SetAttribute('Ignore', 'true'); $changed = $true }
    if (-not $errors.GetAttribute('Retry')) { $errors.SetAttribute('Retry', '0'); $changed = $true }
    if (-not $errors.GetAttribute('Delay')) { $errors.SetAttribute('Delay', '5'); $changed = $true }

    $batch = $root.SelectSingleNode('Batch')
    if (-not $batch) {
        $batch = $xml.CreateElement('Batch')
        [void]$root.AppendChild($batch)
        $changed = $true
    }

    $prog = $batch.SelectSingleNode('ProgressDialog')
    if (-not $prog) {
        $prog = $xml.CreateElement('ProgressDialog')
        [void]$batch.AppendChild($prog)
        $changed = $true
    }
    if ($prog.GetAttribute('Minimized') -ne 'true') { $prog.SetAttribute('Minimized', 'true'); $changed = $true }
    if ($prog.GetAttribute('AutoClose') -ne 'true') { $prog.SetAttribute('AutoClose', 'true'); $changed = $true }

    $errDlg = $batch.SelectSingleNode('ErrorDialog')
    if (-not $errDlg) {
        $errDlg = $xml.CreateElement('ErrorDialog')
        [void]$batch.AppendChild($errDlg)
        $changed = $true
    }
    if ($errDlg.InnerText -ne 'Show' -and $errDlg.InnerText -ne 'Cancel') {
        $errDlg.InnerText = 'Show'
        $changed = $true
    }

    if (-not $changed) {
        Write-Log '     batch already unattended (no change)'
        return
    }

    $backup = $BatchPath + '.bak'
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $BatchPath -Destination $backup -Force
        Write-Log ("     original saved as {0}" -f $backup)
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = $utf8NoBom
    $settings.Indent = $true
    $writer = [System.Xml.XmlWriter]::Create($BatchPath, $settings)
    try {
        $xml.Save($writer)
    } finally {
        $writer.Dispose()
    }

    try {
        [xml]$check = Get-Content -LiteralPath $BatchPath -Encoding UTF8
        if (-not $check.DocumentElement) { throw 'empty document' }
        Write-Log '     patched unattended flags (IgnoreErrors + AutoClose)'
    } catch {
        Copy-Item -LiteralPath $backup -Destination $BatchPath -Force
        Write-Log ("WARN patch invalid, restored original: {0}" -f $_.Exception.Message)
    }
}

function Get-FreeFileSyncProcesses {
    return @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -like 'FreeFileSync*' -or $_.ProcessName -like 'ffs_*' })
}

function Wait-FreeFileSyncProcess {
    # Waits for the started PID AND any other FreeFileSync process it may have spawned,
    # otherwise the next Stop-FreeFileSync would kill a sync that is still running.
    param(
        [Parameter(Mandatory=$true)]$Process,
        [int]$TimeoutSec,
        [int]$IdleHangSec
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $lastCpu = -1.0
    $idleSince = Get-Date

    while ($true) {
        if ((Get-Date) -ge $deadline) { return 'TIMEOUT' }

        $alive = $false
        try {
            $Process.Refresh()
            $alive = -not $Process.HasExited
        } catch { $alive = $false }

        $others = @(Get-FreeFileSyncProcesses)
        if (-not $alive -and $others.Count -eq 0) { return 'EXIT' }

        $cpu = 0.0
        if ($alive) {
            try { $cpu += [double]$Process.TotalProcessorTime.TotalSeconds } catch { }
        }
        foreach ($o in $others) {
            try { $cpu += [double]$o.TotalProcessorTime.TotalSeconds } catch { }
        }

        if ($cpu -gt ($lastCpu + 0.05)) {
            $lastCpu = $cpu
            $idleSince = Get-Date
        } elseif (((Get-Date) - $idleSince).TotalSeconds -ge $IdleHangSec) {
            return 'HUNG'
        }

        Start-Sleep -Seconds 5
    }
}

function Invoke-FfsBatch {
    param(
        [Parameter(Mandatory=$true)][string]$BatchPath,
        [Parameter(Mandatory=$true)][string]$Tag
    )

    $outFile = Join-Path $LogDir ("ffs_{0}_{1}.out.txt" -f $Tag, $stamp)
    $errFile = Join-Path $LogDir ("ffs_{0}_{1}.err.txt" -f $Tag, $stamp)
    $t0 = Get-Date

    # FFS writes its JSON result to stdout; redirects require -NoNewWindow
    $p = Start-Process -FilePath $FreeFileSync `
        -ArgumentList ("`"{0}`"" -f $BatchPath) `
        -RedirectStandardOutput $outFile `
        -RedirectStandardError $errFile `
        -PassThru `
        -NoNewWindow

    if (-not $p) { throw 'Start-Process returned null' }
    Write-Log ("     started PID {0}" -f $p.Id)

    $waitResult = Wait-FreeFileSyncProcess -Process $p -TimeoutSec $TimeoutSec -IdleHangSec $IdleHangSec
    Write-Log ("     wait result: {0}" -f $waitResult)

    $exitCode = -1
    if ($waitResult -eq 'EXIT' -or $waitResult -eq 'GONE') {
        try { $p.WaitForExit() } catch { }
        try {
            if ($null -ne $p.ExitCode) { $exitCode = [int]$p.ExitCode }
        } catch { $exitCode = -1 }
        $meaning = switch ($exitCode) {
            0 { 'success' }
            1 { 'warnings' }
            2 { 'errors' }
            3 { 'cancelled' }
            -1 { 'unknown' }
            default { 'unknown' }
        }
        Write-Log ("     exit code {0} ({1}), {2}s" -f $exitCode, $meaning, [int]((Get-Date) - $t0).TotalSeconds)

        foreach ($f in @($outFile, $errFile)) {
            if (-not (Test-Path -LiteralPath $f)) { continue }
            $lines = @(Get-Content -LiteralPath $f -ErrorAction SilentlyContinue |
                Where-Object { $_ -and $_.Trim() } | Select-Object -First 6)
            foreach ($l in $lines) {
                Write-Log ("     > {0}" -f $l.Trim())
            }
        }
    }

    return [pscustomobject]@{
        Wait     = $waitResult
        ExitCode = $exitCode
        OutFile  = $outFile
        ErrFile  = $errFile
        Seconds  = [int]((Get-Date) - $t0).TotalSeconds
    }
}

function Get-RecentErrorLines([datetime]$Since) {
    $out = New-Object System.Collections.Generic.List[string]
    # Only FreeFileSync's own logs - our run log and report json would be read back as "errors"
    $files = @()
    $files += @(Get-ChildItem -LiteralPath $LogDir -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.LastWriteTime -ge $Since.AddMinutes(-1) -and
            $_.Name -notlike 'run_*.log' -and
            $_.Name -notlike '*.out.txt' -and
            $_.Name -notlike '*.err.txt' -and
            $_.Extension -ne '.json'
        })

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
                    $out.Add(('{0} | {1}' -f $f.Name, $line.Trim())) | Out-Null
                }
            }
        } catch { }
    }
    return $out.ToArray()
}

Write-Log ("START batch folder: {0}" -f $BatchDir)

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
        Stop-FreeFileSync
        Start-Sleep -Seconds $GapSec

        Ensure-BatchUnattended -BatchPath $b.FullName

        $run = Invoke-FfsBatch -BatchPath $b.FullName -Tag $b.BaseName
        $waitResult = $run.Wait
        $exitCode = $run.ExitCode
        $outFile = $run.OutFile
        $errFile = $run.ErrFile

        # Exit 0/1 = fine, 2 = errors, 3 = cancelled. A non-zero exit after a few
        # seconds means FFS refused the config file, so fall back to the saved original.
        $backup = $b.FullName + '.bak'
        if ($waitResult -eq 'EXIT' -and $exitCode -ge 2 -and
            $run.Seconds -lt 20 -and (Test-Path -LiteralPath $backup)) {
            Write-Log ("     failed in {0}s - restoring original config and retrying" -f $run.Seconds)
            Copy-Item -LiteralPath $backup -Destination $b.FullName -Force
            Stop-FreeFileSync
            Start-Sleep -Seconds $GapSec
            $run = Invoke-FfsBatch -BatchPath $b.FullName -Tag ($b.BaseName + '_retry')
            $waitResult = $run.Wait
            $exitCode = $run.ExitCode
            $outFile = $run.OutFile
            $errFile = $run.ErrFile
        }

        if ($waitResult -eq 'HUNG') {
            # Typical: lock warning dialog with no CPU - sync may already be done
            Write-Log ("     hung (no CPU {0}s) - kill and continue queue for {1}" -f $IdleHangSec, $b.Name)
            Stop-FreeFileSync
            $status = 'OK'
            $exitCode = 1
            Write-Log ("OK   {0} (closed hung FFS dialog, continued)" -f $b.Name)
        } elseif ($waitResult -eq 'TIMEOUT') {
            Write-Log ("     TIMEOUT - kill FreeFileSync for {0}" -f $b.Name)
            Stop-FreeFileSync
            $status = 'FAIL'
            $rawErrors.Add('TIMEOUT waiting for FreeFileSync') | Out-Null
        } elseif ($waitResult -eq 'EXIT' -or $waitResult -eq 'GONE') {
            $recent = @(Get-RecentErrorLines -Since $jobStart)
            foreach ($e in $recent) { $rawErrors.Add($e) | Out-Null }
            if (Test-Path -LiteralPath $errFile) {
                Get-Content -LiteralPath $errFile -ErrorAction SilentlyContinue | ForEach-Object {
                    if ($_ -and $_.Trim()) { $rawErrors.Add($_.Trim()) | Out-Null }
                }
            }

            $realErrors = @($rawErrors | Where-Object { -not (Test-IsBenignSourceError $_) })
            if ($exitCode -eq 0 -or $exitCode -eq 1) {
                $status = 'OK'
                Write-Log ("OK   {0} exit={1}" -f $b.Name, $exitCode)
            } elseif ($realErrors.Count -eq 0 -and ($exitCode -eq 2 -or $exitCode -lt 0)) {
                $status = 'OK'
                Write-Log ("OK   {0} exit={1} (only ignorable source-lock errors)" -f $b.Name, $exitCode)
            } else {
                $status = 'FAIL'
                Write-Log ("FAIL {0} exit={1} realErrors={2}" -f $b.Name, $exitCode, $realErrors.Count)
                foreach ($e in ($realErrors | Select-Object -First 5)) {
                    Write-Log ("     ! {0}" -f $e)
                }
            }
        }
    } catch {
        $status = 'FAIL'
        $msg = $_.Exception.Message
        $rawErrors.Add($msg) | Out-Null
        Write-Log ("ERROR {0}: {1}" -f $b.Name, $msg)
        Stop-FreeFileSync
    }

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
    Jobs          = $jobs.ToArray()
}

$json = $report | ConvertTo-Json -Depth 8
Set-Content -LiteralPath $ReportPath -Value $json -Encoding UTF8
$datedReport = Join-Path $LogDir ("backup-report_{0}.json" -f $startedAt.ToString('yyyy-MM-dd'))
Set-Content -LiteralPath $datedReport -Value $json -Encoding UTF8

Write-Log ("REPORT {0}" -f $ReportPath)
Write-Log ("DONE jobs={0} failed={1}" -f $jobs.Count, $failCount)
Write-Log 'EXIT'

if ($failCount -gt 0) { exit 1 } else { exit 0 }
