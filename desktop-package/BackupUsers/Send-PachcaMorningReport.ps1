#Requires -Version 5.1
# Morning run (09:00): read last night backup report and send to Pachca.
# Uses pachca-config.ps1 in the same folder.

$ErrorActionPreference = 'Stop'

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir     = Join-Path $env:USERPROFILE 'Documents\BackupBatchLogs'
$ReportPath = Join-Path $LogDir 'last-backup-report.json'
$ConfigPath = Join-Path $ScriptDir 'pachca-config.ps1'
$Sender     = Join-Path $ScriptDir 'Send-PachcaMessage.ps1'

if (-not (Test-Path -LiteralPath $ReportPath)) {
    throw "Report not found: $ReportPath (night backup did not write it)"
}
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Missing $ConfigPath"
}
if (-not (Test-Path -LiteralPath $Sender)) {
    throw "Missing $Sender"
}

. $ConfigPath
$prefix = if ($PachcaNotifyPrefix) { $PachcaNotifyPrefix } else { '@Backup_bot LS1 backup' }

$report = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add($prefix) | Out-Null
$lines.Add('') | Out-Null
$lines.Add(('Date: {0}' -f $report.RunDate)) | Out-Null
$lines.Add(('Window: {0} - {1}' -f $report.StartedLocal, $report.FinishedLocal)) | Out-Null
$lines.Add(('Server: {0}' -f $report.Server)) | Out-Null
$lines.Add(('Jobs: {0} | Failed: {1}' -f $report.JobsTotal, $report.JobsFailed)) | Out-Null
$lines.Add('') | Out-Null

foreach ($j in $report.Jobs) {
    $mark = if ($j.Status -eq 'OK') { 'OK' } else { 'FAIL' }
    $lines.Add(('User: {0}' -f $j.User)) | Out-Null
    $lines.Add(('  Result: {0}' -f $mark)) | Out-Null
    $lines.Add(('  Time: {0} ({1}s)' -f $j.FinishedLocal, $j.DurationSec)) | Out-Null
    $lines.Add(('  Batch: {0}' -f $j.Batch)) | Out-Null

    $errs = @($j.Errors)
    if ($errs.Count -gt 0) {
        $lines.Add('  Errors:') | Out-Null
        foreach ($e in $errs) {
            # Extra safety filter (should already be filtered at night)
            if ($e -match 'sync\.ffs_lock|sync\.ffs_db') { continue }
            $lines.Add(('   - {0}' -f $e)) | Out-Null
        }
    } else {
        $lines.Add('  Errors: none (source lock warnings ignored)') | Out-Null
    }
    $lines.Add('') | Out-Null
}

$lines.Add(('Log: {0}' -f $report.RunLog)) | Out-Null

$text = ($lines -join "`n")
& $Sender -Message $text -ConfigPath $ConfigPath
Write-Host 'Morning Pachca report sent.'
