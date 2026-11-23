#Requires -Version 5.1
# Send a text message to Pachca via incoming webhook URL.
# Webhook URL is read from pachca-config.ps1 (same folder).

param(
    [Parameter(Mandatory = $false)]
    [string]$Message,

    [Parameter(Mandatory = $false)]
    [string]$WebhookUrl,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'pachca-config.ps1')
)

$ErrorActionPreference = 'Stop'

if (-not $WebhookUrl) {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config not found: $ConfigPath  (copy pachca-config.example.ps1 to pachca-config.ps1)"
    }
    . $ConfigPath
    if (-not $PachcaWebhookUrl) {
        throw 'Set $PachcaWebhookUrl in pachca-config.ps1'
    }
    $WebhookUrl = $PachcaWebhookUrl
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
