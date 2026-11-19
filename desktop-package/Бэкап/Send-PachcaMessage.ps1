#Requires -Version 5.1
# Send a text message to Pachca via incoming webhook URL.
# Bot: Backup (@Backup_bot)

param(
    [Parameter(Mandatory = $false)]
    [string]$Message,

    [Parameter(Mandatory = $false)]
    [string]$WebhookUrl,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'pachca-config.ps1')
)

$ErrorActionPreference = 'Stop'

# Defaults for LS1 / bot Backup
$DefaultWebhookUrl = 'https://api.pachca.com/webhooks/01M7SFTC8WAETX7XVNX2QNE85N'

if (-not $WebhookUrl) {
    if (Test-Path -LiteralPath $ConfigPath) {
        . $ConfigPath
        if ($PachcaWebhookUrl) { $WebhookUrl = $PachcaWebhookUrl }
    }
}
if (-not $WebhookUrl) {
    $WebhookUrl = $DefaultWebhookUrl
}

if (-not $Message) {
    throw 'Pass -Message "text"'
}

$bodyObj = @{ message = $Message }
$json = $bodyObj | ConvertTo-Json -Compress

try {
    $resp = Invoke-WebRequest -Uri $WebhookUrl -Method Post `
        -ContentType 'application/json; charset=utf-8' `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) `
        -UseBasicParsing
    $text = $resp.Content
    if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
        Write-Host ("Pachca OK: {0}" -f $text)
        exit 0
    }
    Write-Warning ("Pachca unexpected status {0}: {1}" -f $resp.StatusCode, $text)
    exit 1
} catch {
    Write-Warning ("Pachca send failed: {0}" -f $_.Exception.Message)
    exit 1
}
