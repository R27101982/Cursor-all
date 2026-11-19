#Requires -Version 5.1
# Runs all FreeFileSync batch jobs in a folder, one after another,
# then sends a summary to Pachca (optional).
#
# Task Scheduler:
#   Program:  powershell.exe
#   Arguments:
#     -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Users\admin\Desktop\BackupUsers\Run-AllBackupBatches.ps1"

$ErrorActionPreference = 'Stop'

# --- configure ---
$BatchDir = Join-Path $env:USERPROFILE 'Documents'
$FreeFileSync = 'C:\Program Files\FreeFileSync\FreeFileSync.exe'
$LogDir       = Join-Path $env:USERPROFILE 'Documents\BackupBatchLogs'
$Filter       = 'BatchRun*.ffs_batch'
$TimeoutSec   = 6 * 60 * 60

$ScriptDir        = Split-Path -Parent $MyInvocation.MyCommand.Path
$PachcaSender     = Join-Path $ScriptDir 'Send-PachcaMessage.ps1'
$PachcaConfig     = Join-Path $ScriptDir 'pachca-config.ps1'
$EnablePachcaNotify = $true
# Pachca bot Backup (@Backup_bot) — webhook is defaulted inside Send-PachcaMessage.ps1
$PachcaNotifyPrefix = '@Backup_bot LS1 backup'
# --- end configure ---

if (-not (Test-Path -LiteralPath $FreeFileSync)) {
    throw "FreeFileSync not found: $FreeFileSync"
}
if (-not (Test-Path -LiteralPath $BatchDir)) {
    throw "Batch folder not found: $BatchDir"
}
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$runLog = Join-Path $LogDir ("run_{0}.log" -f $stamp)
$startedAt = Get-Date
$results = New-Object System.Collections.Generic.List[object]

function Write-Log([string]$Message) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $runLog -Value $line -Encoding UTF8
    Write-Host $line
}

function Send-Pachca([string]$Text) {
    if (-not $EnablePachcaNotify) { return }
    if (-not (Test-Path -LiteralPath $PachcaSender)) {
        Write-Log 'Pachca sender script missing - skip notify'
        return
    }
    try {
        if (Test-Path -LiteralPath $PachcaConfig) {
            & $PachcaSender -Message $Text -ConfigPath $PachcaConfig | Out-Host
        } else {
            & $PachcaSender -Message $Text | Out-Host
        }
        Write-Log 'Pachca notify sent'
    } catch {
        Write-Log ("Pachca notify failed: {0}" -f $_.Exception.Message)
    }
}

Write-Log ("START batch folder: {0}" -f $BatchDir)

$batches = @(Get-ChildItem -LiteralPath $BatchDir -Filter $Filter -File | Sort-Object Name)

if ($batches.Count -eq 0) {
    Write-Log ("No files matching {0} in {1}" -f $Filter, $BatchDir)
    Send-Pachca ("LS1 backup: no BatchRun*.ffs_batch in {0}" -f $BatchDir)
    exit 0
}

$failed = 0
foreach ($b in $batches) {
    Write-Log ("RUN  {0}" -f $b.FullName)
    $jobStart = Get-Date

    $p = Start-Process -FilePath $FreeFileSync `
        -ArgumentList("`"{0}`"" -f $b.FullName) `
        -PassThru `
        -WindowStyle Hidden

    $exited = $true
    try {
        Wait-Process -Id $p.Id -Timeout $TimeoutSec -ErrorAction Stop
    } catch {
        $exited = $false
    }

    $status = 'OK'
    $code = -1
    if (-not $exited -or -not $p.HasExited) {
        Write-Log ("TIMEOUT {0} after {1}s - killing process" -f $b.Name, $TimeoutSec)
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        Get-Process -Name 'FreeFileSync*','ffs_*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        $status = 'TIMEOUT'
        $failed++
    } else {
        $p.Refresh()
        $code = $p.ExitCode
        if ($code -eq 0) {
            Write-Log ("OK   {0} (exit {1})" -f $b.Name, $code)
            $status = 'OK'
        } else {
            # FreeFileSync often returns non-zero when there were warnings (e.g. sync.ffs_lock)
            Write-Log ("WARN {0} (exit {1})" -f $b.Name, $code)
            $status = 'WARN'
            $failed++
        }
    }

    $sec = [int]((Get-Date) - $jobStart).TotalSeconds
    $results.Add([pscustomobject]@{
        Name   = $b.BaseName
        Status = $status
        Exit   = $code
        Sec    = $sec
    }) | Out-Null
}

$elapsed = [int]((Get-Date) - $startedAt).TotalSeconds
Write-Log ("DONE. Jobs: {0}; problems: {1}; {2}s" -f $batches.Count, $failed, $elapsed)
Write-Log 'EXIT'

# Build Pachca message
$prefix = $PachcaNotifyPrefix
if (Test-Path -LiteralPath $PachcaConfig) {
    . $PachcaConfig
    if ($PachcaNotifyPrefix) { $prefix = $PachcaNotifyPrefix }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add(('{0}' -f $prefix)) | Out-Null
$lines.Add(('{0:yyyy-MM-dd HH:mm} | jobs: {1} | problems: {2} | {3}s' -f (Get-Date), $batches.Count, $failed, $elapsed)) | Out-Null
foreach ($r in $results) {
    $lines.Add(('- {0}: {1} (exit {2}, {3}s)' -f $r.Name, $r.Status, $r.Exit, $r.Sec)) | Out-Null
}
$lines.Add(('log: {0}' -f $runLog)) | Out-Null
# Note about typical lock warning on read-only source shares
$lines.Add('note: sync.ffs_lock Access Denied on source shares is expected (read-only)') | Out-Null

Send-Pachca ($lines -join "`n")

if ($failed -gt 0) { exit 1 } else { exit 0 }
