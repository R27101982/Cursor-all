#Requires -Version 5.1
# Runs all FreeFileSync batch jobs in a folder, one after another.
# Schedule this script daily at 00:00 via Task Scheduler (local PC time).

$ErrorActionPreference = 'Stop'

# --- configure ---
$BatchDir = Join-Path $env:USERPROFILE 'Documents'
# Or fixed path, e.g.:
# $BatchDir = 'C:\Users\admin\Documents'

$FreeFileSync = 'C:\Program Files\FreeFileSync\FreeFileSync.exe'
$LogDir       = Join-Path $env:USERPROFILE 'Documents\BackupBatchLogs'
$Filter       = 'BatchRun*.ffs_batch'   # BatchRunPotapov.ffs_batch, BatchRunKartashov.ffs_batch, ...
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

$batches = Get-ChildItem -LiteralPath $BatchDir -Filter $Filter -File |
    Sort-Object Name

if (-not $batches) {
    Write-Log ("No files matching {0} in {1}" -f $Filter, $BatchDir)
    exit 0
}

$failed = 0
foreach ($b in $batches) {
    Write-Log ("RUN  {0}" -f $b.FullName)
    $p = Start-Process -FilePath $FreeFileSync -ArgumentList @('"' + $b.FullName + '"') -Wait -PassThru -WindowStyle Hidden
    $code = $p.ExitCode
    if ($code -eq 0) {
        Write-Log ("OK   {0} (exit {1})" -f $b.Name, $code)
    } else {
        # FreeFileSync: 0=success, other codes = warnings/errors depending on version
        Write-Log ("WARN {0} (exit {1})" -f $b.Name, $code)
        $failed++
    }
}

Write-Log ("DONE. Jobs: {0}; non-zero exits: {1}" -f $batches.Count, $failed)
if ($failed -gt 0) { exit 1 } else { exit 0 }
