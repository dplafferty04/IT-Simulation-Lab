#
# 00-helpdesk-common.ps1 — Shared functions dot-sourced by all helpdesk scripts.
# Not run directly. Each script begins with: . "$PSScriptRoot\00-helpdesk-common.ps1"
#

# ── Log Configuration ─────────────────────────────────────────
$script:LogDir  = "C:\IT\Logs\Helpdesk"
$script:LogFile = Join-Path $script:LogDir ("helpdesk-{0}.log" -f (Get-Date -Format "yyyy-MM"))
$script:TicketNumber = $null   # set per-session by the calling script

function Initialize-HelpDeskLog {
    if (-not (Test-Path $script:LogDir)) {
        New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
    }
}

function Write-HDLog {
    param(
        [string]$Message,
        [ValidateSet("INFO","OK","WARN","ERROR","ACTION")]
        [string]$Level = "INFO"
    )
    Initialize-HelpDeskLog
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $agent     = $env:USERNAME
    $ticket    = if ($script:TicketNumber) { " [TKT:$($script:TicketNumber)]" } else { "" }
    $line      = "[$timestamp][$Level]$ticket [$agent] $Message"
    Add-Content -Path $script:LogFile -Value $line -Encoding UTF8

    $color = switch ($Level) {
        "OK"     { "Green" }
        "WARN"   { "Yellow" }
        "ERROR"  { "Red" }
        "ACTION" { "Magenta" }
        default  { "Cyan" }
    }
    Write-Host "  [$Level] $Message" -ForegroundColor $color
}

# ── Console helpers ───────────────────────────────────────────
function Write-Banner {
    param([string]$Title, [string]$Ticket = "")
    $width = 54
    Write-Host ""
    Write-Host ("═" * $width) -ForegroundColor DarkCyan
    Write-Host ("  {0}" -f $Title) -ForegroundColor Cyan
    if ($Ticket) { Write-Host ("  Ticket: {0}" -f $Ticket) -ForegroundColor DarkGray }
    Write-Host ("  Agent : {0} @ {1}" -f $env:USERNAME, $env:COMPUTERNAME) -ForegroundColor DarkGray
    Write-Host ("  Time  : {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) -ForegroundColor DarkGray
    Write-Host ("═" * $width) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Result {
    param([string]$Label, [string]$Value, [string]$Color = "White")
    Write-Host ("  {0,-22} {1}" -f ($Label + ":"), $Value) -ForegroundColor $Color
}

function Confirm-Action {
    param([string]$Prompt)
    $answer = Read-Host "`n  $Prompt [y/N]"
    return ($answer -match '^[Yy]$')
}

# ── AD helpers ────────────────────────────────────────────────
function Get-ValidatedADUser {
    param([string]$Username)
    try {
        $user = Get-ADUser -Identity $Username `
            -Properties LockedOut, Enabled, PasswordExpired, PasswordLastSet,
                         LastLogonDate, Department, Title, Manager,
                         DistinguishedName, EmailAddress `
            -ErrorAction Stop
        return $user
    } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-HDLog "User not found in AD: $Username" "ERROR"
        return $null
    } catch {
        Write-HDLog "AD lookup failed for '$Username': $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Show-UserSummary {
    param($User)
    $managerName = if ($User.Manager) {
        try { (Get-ADUser -Identity $User.Manager).Name } catch { $User.Manager }
    } else { "N/A" }

    $status = @()
    if (-not $User.Enabled)       { $status += "DISABLED" }
    if ($User.LockedOut)          { $status += "LOCKED" }
    if ($User.PasswordExpired)    { $status += "PW-EXPIRED" }
    $statusStr = if ($status) { $status -join ", " } else { "Active" }

    Write-Host ""
    Write-Host "  ── Account Summary ──────────────────────" -ForegroundColor DarkGray
    Write-Result "Display Name"   $User.Name
    Write-Result "Username"       $User.SamAccountName
    Write-Result "Department"     ($User.Department ?? "N/A")
    Write-Result "Title"          ($User.Title ?? "N/A")
    Write-Result "Manager"        $managerName
    Write-Result "Email"          ($User.EmailAddress ?? "N/A")
    Write-Result "Status"         $statusStr $(if ($status) { "Yellow" } else { "Green" })
    Write-Result "Last Logon"     $(if ($User.LastLogonDate) { $User.LastLogonDate.ToString("yyyy-MM-dd HH:mm") } else { "Never" })
    Write-Result "PW Last Set"    $(if ($User.PasswordLastSet) { $User.PasswordLastSet.ToString("yyyy-MM-dd HH:mm") } else { "Never" })
    Write-Host ""
}

# ── Password generator ────────────────────────────────────────
function New-TempPassword {
    # Generates a readable temporary password meeting CorpTech's policy:
    # 14+ chars, upper, lower, digit, special — NO ambiguous chars (0/O, l/1/I)
    $upper   = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    $lower   = "abcdefghjkmnpqrstuvwxyz"
    $digits  = "23456789"
    $special = "!@#$%^&*"

    $pw  = ($upper  | Get-Random -Count 2 | ForEach-Object { [char]$_ }) -join ''
    $pw += ($lower  | Get-Random -Count 4 | ForEach-Object { [char]$_ }) -join ''
    $pw += ($digits | Get-Random -Count 3 | ForEach-Object { [char]$_ }) -join ''
    $pw += ($special| Get-Random -Count 2 | ForEach-Object { [char]$_ }) -join ''
    # Shuffle the result so it's not always pattern-predictable
    $pw = ($pw.ToCharArray() | Get-Random -Count $pw.Length) -join ''

    # Pad to 14 if needed
    while ($pw.Length -lt 14) { $pw += ($digits | Get-Random -Count 1) }
    return $pw
}

# ── Require RSAT ──────────────────────────────────────────────
function Assert-ADModule {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Host "  [ERROR] ActiveDirectory module not found." -ForegroundColor Red
        Write-Host "          Install RSAT: Add-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'" -ForegroundColor Yellow
        exit 1
    }
    Import-Module ActiveDirectory -ErrorAction Stop
}
