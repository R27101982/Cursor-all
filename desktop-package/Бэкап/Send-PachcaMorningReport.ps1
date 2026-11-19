#Requires -Version 5.1
# Morning 09:00: compact Pachca report from last-backup-report.json
# One message for all users. Fields only:
#   Date, Time, User, Result, Errors

$ErrorActionPreference = 'Stop'

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir     = Join-Path $env:USERPROFILE 'Documents\BackupBatchLogs'
$ReportPath = Join-Path $LogDir 'last-backup-report.json'
$ConfigPath = Join-Path $ScriptDir 'pachca-config.ps1'
$Sender     = Join-Path $ScriptDir 'Send-PachcaMessage.ps1'

if (-not (Test-Path -LiteralPath $ReportPath)) {
    throw "Report not found: $ReportPath"
}
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Missing $ConfigPath"
}
if (-not (Test-Path -LiteralPath $Sender)) {
    throw "Missing $Sender"
}

. $ConfigPath

$report = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$date = $report.RunDate

$lines = New-Object System.Collections.Generic.List[string]
# optional mention from config prefix (e.g. @Backup_bot) — one line, then compact rows
if ($PachcaNotifyPrefix) {
    $lines.Add($PachcaNotifyPrefix) | Out-Null
}

foreach ($j in $report.Jobs) {
    $result = if ($j.Status -eq 'OK') { 'OK' } else { 'FAIL' }

    $errText = 'none'
    $errs = @($j.Errors)
    if ($errs.Count -gt 0) {
        $clean = @()
        foreach ($e in $errs) {
            if ($e -match 'sync\.ffs_lock|sync\.ffs_db') { continue }
            $clean += $e
        }
        if ($clean.Count -gt 0) {
            $errText = ($clean -join '; ')
        }
    }

    $line = 'Date: {0}, Time: {1} ({2}s), User: {3}, Result: {4}, Errors: {5}' -f `
        $date, $j.FinishedLocal, $j.DurationSec, $j.User, $result, $errText
    $lines.Add($line) | Out-Null
}

if ($lines.Count -eq 0 -or ($lines.Count -eq 1 -and $PachcaNotifyPrefix)) {
    $lines.Add(('Date: {0}, Time: {1}, User: -, Result: FAIL, Errors: no jobs in report' -f $date, $report.FinishedLocal)) | Out-Null
}

$text = ($lines -join "`n")
& $Sender -Message $text -ConfigPath $ConfigPath
Write-Host 'Morning Pachca report sent.'
