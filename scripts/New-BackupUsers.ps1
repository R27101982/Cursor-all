#Requires -RunAsAdministrator
# ASCII-only source for Windows PowerShell 5.1 (no UTF-8 BOM issues with Cyrillic).
# Target: LS1, run as admin from C:\Users\admin\Desktop\BackupUsers\

$ErrorActionPreference = 'Stop'

# "Polzovateli.txt" Cyrillic filename built from codepoints (avoids encoding breakage)
$UsersListName = -join ([char[]]@(0x041F,0x043E,0x043B,0x044C,0x0437,0x043E,0x0432,0x0430,0x0442,0x0435,0x043B,0x0438)) + '.txt'
$DesktopDir    = 'C:\Users\admin\Desktop'
$UsersFile     = Join-Path $DesktopDir $UsersListName
$UsersFileAlt  = Join-Path $DesktopDir 'Users.txt'   # ASCII fallback
$PasswordsFile = Join-Path $DesktopDir 'user-passwords.txt'
$BackupRoot    = Join-Path $DesktopDir 'Backup'
$GroupName     = 'Quantor'
$AdminUser     = "$env:COMPUTERNAME\admin"

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-RandomPassword {
    param([int]$Length = 8)
    $digits  = '23456789'.ToCharArray()
    $letters = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'.ToCharArray()
    $all     = $digits + $letters

    do {
        $chars = 1..$Length | ForEach-Object { $all | Get-Random }
        $pwd   = -join $chars
        $hasDigit  = $pwd -match '\d'
        $hasLetter = $pwd -match '[A-Za-z]'
    } while (-not ($hasDigit -and $hasLetter))

    return $pwd
}

function Deny-InteractiveLogon {
    param([Parameter(Mandatory)][string]$UserName)

    $sid = $null
    try {
        $sid = ([Security.Principal.NTAccount]"$env:COMPUTERNAME\$UserName").
            Translate([Security.Principal.SecurityIdentifier]).Value
    } catch {
        Write-Warning "Cannot resolve SID for $UserName. Skip Deny logon."
        return
    }
    $principal = "*$sid"

    $export = Join-Path $env:TEMP ("secpol_export_{0}.inf" -f [guid]::NewGuid().ToString('N'))
    $import = Join-Path $env:TEMP ("secpol_import_{0}.inf" -f [guid]::NewGuid().ToString('N'))
    $db     = Join-Path $env:TEMP ("secpol_{0}.sdb" -f [guid]::NewGuid().ToString('N'))

    try {
        $exportOut = & secedit.exe /export /cfg $export /areas USER_RIGHTS 2>&1
        if (-not (Test-Path $export)) {
            Write-Warning "secedit export failed for $UserName. $exportOut"
            return
        }

        $content = Get-Content -Path $export -Encoding Unicode
        $rights = @(
            'SeDenyInteractiveLogonRight',
            'SeDenyRemoteInteractiveLogonRight'
        )

        $newLines = foreach ($line in $content) {
            $matched = $false
            foreach ($right in $rights) {
                if ($line -match ("^\s*{0}\s*=" -f [regex]::Escape($right))) {
                    $matched = $true
                    if ($line -notmatch [regex]::Escape($principal)) {
                        if ($line -match '=\s*$') {
                            "$right = $principal"
                        } else {
                            "$line,$principal"
                        }
                    } else {
                        $line
                    }
                    break
                }
            }
            if (-not $matched) { $line }
        }

        foreach ($right in $rights) {
            $exists = $newLines | Where-Object { $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($right)) }
            if (-not $exists) {
                $newLines += "$right = $principal"
            }
        }

        $header = @(
            '[Unicode]'
            'Unicode=yes'
            '[Version]'
            'signature="$CHICAGO$"'
            'Revision=1'
            '[Privilege Rights]'
        )
        $privLines = $newLines | Where-Object { $_ -match '^\s*Se\w+\s*=' }
        Set-Content -Path $import -Value ($header + $privLines) -Encoding Unicode

        $cfgOut = & secedit.exe /configure /db $db /cfg $import /areas USER_RIGHTS 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "secedit configure failed for $UserName (exit $LASTEXITCODE). $cfgOut"
        }
    }
    finally {
        Remove-Item -Path $export, $import, $db -Force -ErrorAction SilentlyContinue
    }
}

function Set-BackupFolderAcl {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$UserName
    )

    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)

    $inherit = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor `
               [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $propagate = [Security.AccessControl.PropagationFlags]::None
    $typeAllow = [Security.AccessControl.AccessControlType]::Allow

    $full = [Security.AccessControl.FileSystemRights]::FullControl
    $readExec = [Security.AccessControl.FileSystemRights]::ReadAndExecute

    $system = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($system, $full, $inherit, $propagate, $typeAllow)))

    $admins = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($admins, $full, $inherit, $propagate, $typeAllow)))

    $adminNt = New-Object Security.Principal.NTAccount($AdminUser)
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($adminNt, $full, $inherit, $propagate, $typeAllow)))

    $userNt = New-Object Security.Principal.NTAccount("$env:COMPUTERNAME\$UserName")
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($userNt, $readExec, $inherit, $propagate, $typeAllow)))

    Set-Acl -Path $Path -AclObject $acl
}

function Get-UserFolderPaths {
    param([string]$UserName)
    @(
        Join-Path $BackupRoot "QformProjects\$UserName\Data"
        Join-Path $BackupRoot "QformProjects\$UserName\Versions"
        Join-Path $BackupRoot "Support\$UserName"
        Join-Path $BackupRoot "Support\$UserName\Data"
        Join-Path $BackupRoot "Support\$UserName\Versions"
    )
}

# --- main ---

if (-not (Test-IsAdministrator)) {
    throw 'Run this script as Administrator.'
}

$listFile = $null
if (Test-Path -LiteralPath $UsersFile) {
    $listFile = $UsersFile
} elseif (Test-Path -LiteralPath $UsersFileAlt) {
    $listFile = $UsersFileAlt
    Write-Host "Using ASCII list file: $UsersFileAlt"
} else {
    throw "Users list not found. Create: $UsersFile  (or $UsersFileAlt)"
}

if (-not (Get-LocalGroup -Name $GroupName -ErrorAction SilentlyContinue)) {
    throw "Local group '$GroupName' not found. Create it first."
}

try {
    $null = ([Security.Principal.NTAccount]$AdminUser).Translate([Security.Principal.SecurityIdentifier])
} catch {
    throw "Account $AdminUser not found."
}

function ConvertTo-UserName {
    param([string]$Line)
    $t = $Line.Trim()
    if (-not $t) { return $null }
    if ($t -match '^\s*#') { return $null }

    # Skip header-like lines
    if ($t -match '(?i)password|username|login') { return $null }
    # Cyrillic header "Polzovatel" / "Parol"
    $hdrUser = -join ([char[]]@(0x041F,0x043E,0x043B,0x044C,0x0437,0x043E,0x0432,0x0430,0x0442,0x0435,0x043B))
    $hdrPass = -join ([char[]]@(0x041F,0x0430,0x0440,0x043E,0x043B))
    if ($t -match [regex]::Escape($hdrUser) -or $t -match [regex]::Escape($hdrPass)) { return $null }

    # "1. Potapov FhU2i-qC9" / "2. Kartashov" / "Potapov"
    if ($t -match '^\s*\d+\.\s*([A-Za-z0-9._-]{1,20})\b') {
        return $Matches[1]
    }
    if ($t -match '^\s*([A-Za-z0-9._-]{1,20})\s*$') {
        return $Matches[1]
    }
    if ($t -match '^\s*([A-Za-z0-9._-]{1,20})\b') {
        return $Matches[1]
    }
    return $null
}

$names = Get-Content -LiteralPath $listFile -Encoding UTF8 |
    ForEach-Object { ConvertTo-UserName $_ } |
    Where-Object { $_ } |
    Select-Object -Unique

if (-not $names) {
    throw "Users list is empty or has no valid names: $listFile. Use one username per line, e.g. Potapov"
}

if (-not (Test-Path -LiteralPath $PasswordsFile)) {
    Set-Content -LiteralPath $PasswordsFile -Value "Username`tPassword`tCreatedUtc" -Encoding UTF8
}

$created = 0
$skipped = 0

# Cyrillic group name "Polzovateli" for built-in Users on RU Windows
$UsersGroupRu = -join ([char[]]@(0x041F,0x043E,0x043B,0x044C,0x0437,0x043E,0x0432,0x0430,0x0442,0x0435,0x043B,0x0438))

foreach ($name in $names) {
    if ($name -notmatch '^[a-zA-Z0-9._-]{1,20}$') {
        Write-Warning "Skip invalid username: '$name'"
        continue
    }

    $existing = Get-LocalUser -Name $name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "[SKIP] User exists: $name (password/folders/ACL not changed)"
        $skipped++
        continue
    }

    Write-Host "[NEW]  Creating user: $name"

    $plain = New-RandomPassword -Length 8
    $secure = ConvertTo-SecureString $plain -AsPlainText -Force

    New-LocalUser -Name $name `
        -Password $secure `
        -FullName $name `
        -Description 'Backup share user (no interactive logon)' `
        -PasswordNeverExpires `
        -UserMayNotChangePassword `
        -AccountNeverExpires | Out-Null

    Add-LocalGroupMember -Group $GroupName -Member $name

    try {
        $usersGroup = Get-LocalGroup -Name 'Users' -ErrorAction SilentlyContinue
        if (-not $usersGroup) {
            $usersGroup = Get-LocalGroup -Name $UsersGroupRu -ErrorAction SilentlyContinue
        }
        if ($usersGroup -and (Get-LocalGroupMember -Group $usersGroup.Name -Member $name -ErrorAction SilentlyContinue)) {
            Remove-LocalGroupMember -Group $usersGroup.Name -Member $name -ErrorAction SilentlyContinue
        }
    } catch { }

    Deny-InteractiveLogon -UserName $name

    $paths = Get-UserFolderPaths -UserName $name
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) {
            New-Item -ItemType Directory -Path $p -Force | Out-Null
        }
        Set-BackupFolderAcl -Path $p -UserName $name
    }

    $line = "{0}`t{1}`t{2:yyyy-MM-dd HH:mm:ss}Z" -f $name, $plain, (Get-Date).ToUniversalTime()
    Add-Content -LiteralPath $PasswordsFile -Value $line -Encoding UTF8

    Write-Host "[OK]   $name created. Folders and ACL ready."
    $created++
}

Write-Host ""
Write-Host "Done. Created: $created; skipped: $skipped."
Write-Host "Passwords: $PasswordsFile"
Write-Host "Keep user-passwords.txt in a safe place."
