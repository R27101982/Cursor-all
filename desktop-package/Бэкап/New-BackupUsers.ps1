#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Создаёт локальных пользователей на LS1, папки бэкапа и ACL.

.DESCRIPTION
  - Читает имена из C:\Users\admin\Desktop\Пользователи.txt (по одному в строке)
  - Если пользователь уже существует — пропускает (не трогает пароль, папки, права)
  - Иначе: создаёт пользователя, 8-символьный пароль (буквы+цифры), пишет в user-passwords.txt
  - Добавляет в группу Quantor
  - Запрещает интерактивный вход и вход по RDP (сетевой доступ к шарам остаётся)
  - Создаёт папки QformProjects/<User>/Data|Versions и Support/<User>/Data|Versions
  - ACL: LS1\admin и Администраторы — Full; пользователь — Read+ReadAndExecute

.EXAMPLE
  # На LS1, под admin, скрипт лежит здесь:
  powershell -ExecutionPolicy Bypass -File C:\Users\admin\Desktop\BackupUsers\New-BackupUsers.ps1
#>

$ErrorActionPreference = 'Stop'

$UsersFile     = 'C:\Users\admin\Desktop\Пользователи.txt'
$PasswordsFile = 'C:\Users\admin\Desktop\user-passwords.txt'
$BackupRoot    = 'C:\Users\admin\Desktop\Backup'
$GroupName     = 'Quantor'
$AdminUser     = "$env:COMPUTERNAME\admin"   # LS1\admin на этом сервере

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-RandomPassword {
    param([int]$Length = 8)
    $digits  = '23456789'.ToCharArray()          # без 0/1 — меньше путаницы
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
    # secedit INF принимает SID в виде *S-1-5-... (не DOMAIN\user)
    $sid = $null
    try {
        $sid = ([Security.Principal.NTAccount]"$env:COMPUTERNAME\$UserName").
            Translate([Security.Principal.SecurityIdentifier]).Value
    } catch {
        Write-Warning "Не удалось получить SID для $UserName. Пропуск Deny logon."
        return
    }
    $principal = "*$sid"

    $export = Join-Path $env:TEMP ("secpol_export_{0}.inf" -f [guid]::NewGuid().ToString('N'))
    $import = Join-Path $env:TEMP ("secpol_import_{0}.inf" -f [guid]::NewGuid().ToString('N'))
    $db     = Join-Path $env:TEMP ("secpol_{0}.sdb" -f [guid]::NewGuid().ToString('N'))

    try {
        $exportOut = & secedit.exe /export /cfg $export /areas USER_RIGHTS 2>&1
        if (-not (Test-Path $export)) {
            Write-Warning "Не удалось экспортировать политику прав. Пропуск Deny logon для $UserName. $exportOut"
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
            Write-Warning "secedit не применил Deny logon для $UserName (код $LASTEXITCODE). $cfgOut"
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
    $acl.SetAccessRuleProtection($true, $false)  # без наследования

    $inherit = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor `
               [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $propagate = [Security.AccessControl.PropagationFlags]::None
    $typeAllow = [Security.AccessControl.AccessControlType]::Allow

    $full = [Security.AccessControl.FileSystemRights]::FullControl
    $readExec = [Security.AccessControl.FileSystemRights]::ReadAndExecute

    # SYSTEM
    $system = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($system, $full, $inherit, $propagate, $typeAllow)))

    # Администраторы (SID — не зависит от языка ОС)
    $admins = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($admins, $full, $inherit, $propagate, $typeAllow)))

    # LS1\admin
    $adminNt = New-Object Security.Principal.NTAccount($AdminUser)
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($adminNt, $full, $inherit, $propagate, $typeAllow)))

    # Созданный пользователь — чтение / чтение и выполнение
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
    throw 'Запустите скрипт от имени администратора.'
}

if (-not (Test-Path -LiteralPath $UsersFile)) {
    throw "Не найден файл списка: $UsersFile"
}

if (-not (Get-LocalGroup -Name $GroupName -ErrorAction SilentlyContinue)) {
    throw "Группа '$GroupName' не найдена. Создайте её заранее."
}

# Проверка, что admin существует
try {
    $null = ([Security.Principal.NTAccount]$AdminUser).Translate([Security.Principal.SecurityIdentifier])
} catch {
    throw "Учётка $AdminUser не найдена."
}

$names = Get-Content -LiteralPath $UsersFile -Encoding UTF8 |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and ($_ -notmatch '^\s*#') }

if (-not $names) {
    throw 'В файле Пользователи.txt нет имён.'
}

if (-not (Test-Path -LiteralPath $PasswordsFile)) {
    Set-Content -LiteralPath $PasswordsFile -Value "Username`tPassword`tCreatedUtc" -Encoding UTF8
}

$created = 0
$skipped = 0

foreach ($name in $names) {
    if ($name -notmatch '^[a-zA-Z0-9._-]{1,20}$') {
        Write-Warning "Пропуск недопустимого имени: '$name'"
        continue
    }

    $existing = Get-LocalUser -Name $name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "[SKIP] Пользователь уже есть: $name — пароль, папки и права не меняем."
        $skipped++
        continue
    }

    Write-Host "[NEW]  Создаём пользователя: $name"

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

    # Убрать из Users, если попал автоматически — снижает право локального входа по умолчанию
    try {
        $usersGroup = Get-LocalGroup -Name 'Users' -ErrorAction SilentlyContinue
        if (-not $usersGroup) {
            $usersGroup = Get-LocalGroup -Name 'Пользователи' -ErrorAction SilentlyContinue
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

    Write-Host "[OK]   $name создан. Папки и ACL готовы."
    $created++
}

Write-Host ""
Write-Host "Готово. Создано: $created; пропущено: $skipped."
Write-Host "Пароли: $PasswordsFile"
Write-Host "Храните user-passwords.txt в безопасном месте."
