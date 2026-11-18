#Requires -Version 5.1
# Runs all FreeFileSync batch jobs in a folder, one after another.
# Schedule daily at 00:00. Use Task Scheduler:
#   Program:  powershell.exe
#   Arguments:
#     -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Users\admin\Desktop\BackupUsers\Run-AllBackupBatches.ps1"
#   Run whether user is logged on or not  (no visible window)

$ErrorActionPreference = 'Stop'

# --- configure ---
$BatchDir = Join-Path $env:USERPROFILE 'Documents'
$FreeFileSync = 'C:\Program Files\FreeFileSync\FreeFileSync.exe'
$LogDir       = Join-Path $env:USERPROFILE 'Documents\BackupBatchLogs'
$Filter       = 'BatchRun*.ffs_batch'
# Max wait per one batch (seconds). Prevents PowerShell hanging forever on a dialog.
$TimeoutSec   = 6 * 60 * 60
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

function Write-Log([string]$Message) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $runLog -Value $line -Encoding UTF8
    Write-Host $line
}

Write-Log ("START batch folder: {0}" -f $BatchDir)

$batches = @(Get-ChildItem -LiteralPath $BatchDir -Filter $Filter -File | Sort-Object Name)

if ($batches.Count -eq 0) {
    Write-Log ("No files matching {0} in {1}" -f $Filter, $BatchDir)
    exit 0
}

$failed = 0
foreach ($b in $batches) {
    Write-Log ("RUN  {0}" -f $b.FullName)

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

    if (-not $exited -or -not $p.HasExited) {
        Write-Log ("TIMEOUT {0} after {1}s - killing process (often a FreeFileSync dialog is waiting)" -f $b.Name, $TimeoutSec)
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        Get-Process -Name 'FreeFileSync*','ffs_*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        $failed++
        continue
    }

    # Refresh exit code
    $p.Refresh()
    $code = $p.ExitCode
    if ($code -eq 0) {
        Write-Log ("OK   {0} (exit {1})" -f $b.Name, $code)
    } else {
        Write-Log ("WARN {0} (exit {1})" -f $b.Name, $code)
        $failed++
    }
}

Write-Log ("DONE. Jobs: {0}; problems: {1}" -f $batches.Count, $failed)
Write-Log 'EXIT'
if ($failed -gt 0) { exit 1 } else { exit 0 }
