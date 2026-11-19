#Requires -Version 5.1
# Morning 09:00: one Pachca message, block per user, blank line between users.
# Pachca markdown has no text color - OK uses green emoji, FAIL uses red emoji.

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

# Pachca webhook markdown has no text color - use green/red circle emoji
$okMark   = [System.Char]::ConvertFromUtf32(0x1F7E2)  # green circle
$failMark = [System.Char]::ConvertFromUtf32(0x1F534)  # red circle

$blocks = New-Object System.Collections.Generic.List[string]
if ($PachcaNotifyPrefix) {
    $blocks.Add($PachcaNotifyPrefix) | Out-Null
}

foreach ($j in $report.Jobs) {
    $isOk = ($j.Status -eq 'OK')
    $resultLine = if ($isOk) {
        "Result: $okMark"
    } else {
        "Result: $failMark"
    }

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

    $block = @(
        ("Date: {0}" -f $date)
        ("Time: {0} ({1}s)" -f $j.FinishedLocal, $j.DurationSec)
        ("User: {0}" -f $j.User)
        $resultLine
        ("Errors: {0}" -f $errText)
    ) -join "`n"

    $blocks.Add($block) | Out-Null
}

if ($blocks.Count -eq 0 -or ($blocks.Count -eq 1 -and $PachcaNotifyPrefix)) {
    $blocks.Add((@(
        ("Date: {0}" -f $date)
        ("Time: {0}" -f $report.FinishedLocal)
        'User: -'
        ("Result: {0}" -f $failMark)
        'Errors: no jobs in report'
    ) -join "`n")) | Out-Null
}

# Blank line between user blocks (and after prefix)
$text = ($blocks -join "`n`n")
& $Sender -Message $text -ConfigPath $ConfigPath
Write-Host 'Morning Pachca report sent.'
