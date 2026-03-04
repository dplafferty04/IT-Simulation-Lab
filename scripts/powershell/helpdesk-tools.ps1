#Requires -RunAsAdministrator
<#
.SYNOPSIS
    CorpTech IT Helpdesk Toolkit — Interactive menu launcher.
    Run this script to get a menu of all helpdesk tasks.
    Each task is fully logged to C:\IT\Logs\Helpdesk\

.NOTES
    Requires RSAT (Active Directory PowerShell module).
    Must be run as a Domain Admin or member of GRP-IT-HelpDesk.
#>

. "$PSScriptRoot\00-helpdesk-common.ps1"
Assert-ADModule

# ── Splash ────────────────────────────────────────────────────
function Show-Splash {
    Clear-Host
    Write-Host @"

  ╔══════════════════════════════════════════════════════╗
  ║        CorpTech IT Helpdesk Toolkit v1.0             ║
  ║        corp.local  |  helpdesk@corp.local            ║
  ╠══════════════════════════════════════════════════════╣
  ║  Agent  : $("{0,-44}" -f "$env:USERNAME @ $env:COMPUTERNAME")║
  ║  Session : $("{0,-44}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))║
  ║  Log     : $("{0,-44}" -f "C:\IT\Logs\Helpdesk\")║
  ╚══════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan
}

# ── Main menu ─────────────────────────────────────────────────
function Show-Menu {
    Write-Host "  ┌─────────────────────────────────────────────┐" -ForegroundColor DarkCyan
    Write-Host "  │  SELECT A TASK                              │" -ForegroundColor DarkCyan
    Write-Host "  ├─────────────────────────────────────────────┤" -ForegroundColor DarkCyan
    Write-Host "  │  1  Reset User Password                     │" -ForegroundColor White
    Write-Host "  │  2  Unlock User Account                     │" -ForegroundColor White
    Write-Host "  │  3  Add / Remove User from Group            │" -ForegroundColor White
    Write-Host "  │  4  Offboard / Disable Departed Employee    │" -ForegroundColor White
    Write-Host "  │  5  Map Network Drive                       │" -ForegroundColor White
    Write-Host "  ├─────────────────────────────────────────────┤" -ForegroundColor DarkCyan
    Write-Host "  │  6  Show Recent Helpdesk Log                │" -ForegroundColor DarkGray
    Write-Host "  │  7  Quick AD User Lookup                    │" -ForegroundColor DarkGray
    Write-Host "  │  8  List All AD Groups                      │" -ForegroundColor DarkGray
    Write-Host "  │  9  Check Domain Health                     │" -ForegroundColor DarkGray
    Write-Host "  ├─────────────────────────────────────────────┤" -ForegroundColor DarkCyan
    Write-Host "  │  Q  Quit                                    │" -ForegroundColor DarkGray
    Write-Host "  └─────────────────────────────────────────────┘" -ForegroundColor DarkCyan
    Write-Host ""
}

# ── Prompt helpers ────────────────────────────────────────────
function Read-RequiredInput {
    param([string]$Prompt, [string]$Default = "")
    $val = ""
    while ($val -eq "") {
        $val = Read-Host "  $Prompt"
        if ($val -eq "" -and $Default -ne "") { $val = $Default }
        if ($val -eq "") { Write-Host "  [!] This field is required." -ForegroundColor Yellow }
    }
    return $val
}

function Read-OptionalInput {
    param([string]$Prompt, [string]$Default = "")
    $val = Read-Host "  $Prompt [${Default}]"
    if ($val -eq "") { return $Default }
    return $val
}

# ── Task dispatchers ──────────────────────────────────────────

function Invoke-PasswordReset {
    Write-Host "`n  ── Password Reset ───────────────────────────`n" -ForegroundColor Cyan
    $user   = Read-RequiredInput "Username (SAM account)"
    $ticket = Read-OptionalInput "Ticket number" ""
    $custom = Read-OptionalInput "Custom password (leave blank to auto-generate)" ""

    $args = @("-Username", $user, "-TicketNumber", $ticket)
    if ($custom) { $args += @("-Password", $custom) }

    & "$PSScriptRoot\01-reset-password.ps1" @args
}

function Invoke-AccountUnlock {
    Write-Host "`n  ── Account Unlock ───────────────────────────`n" -ForegroundColor Cyan
    $user   = Read-RequiredInput "Username (SAM account)"
    $ticket = Read-OptionalInput "Ticket number" ""

    & "$PSScriptRoot\02-unlock-account.ps1" -Username $user -TicketNumber $ticket
}

function Invoke-GroupChange {
    Write-Host "`n  ── Add / Remove User from Group ─────────────`n" -ForegroundColor Cyan
    $user   = Read-RequiredInput "Username (SAM account)"
    $group  = Read-RequiredInput "Group name (full or partial)"
    $ticket = Read-OptionalInput "Ticket number" ""
    $action = Read-OptionalInput "Action: [A]dd or [R]emove" "A"

    $removeSwitch = @{}
    if ($action -match "^[Rr]") { $removeSwitch = @{ Remove = $true } }

    & "$PSScriptRoot\03-add-to-group.ps1" `
        -Username $user -GroupName $group -TicketNumber $ticket @removeSwitch
}

function Invoke-Offboarding {
    Write-Host "`n  ── Offboard Departed Employee ───────────────`n" -ForegroundColor Cyan
    Write-Host "  ⚠  This performs a full account disable + group removal." -ForegroundColor Red
    Write-Host "  ⚠  Ensure you have HR or manager authorization before proceeding.`n" -ForegroundColor Red
    $user   = Read-RequiredInput "Username of departing employee"
    $ticket = Read-OptionalInput "Ticket / HR request number" ""
    $reason = Read-OptionalInput "Reason [Resigned/Terminated/Transferred/LeaveOfAbsence]" "Resigned"

    & "$PSScriptRoot\04-offboard-user.ps1" `
        -Username $user -TicketNumber $ticket -Reason $reason
}

function Invoke-DriveMap {
    Write-Host "`n  ── Map Network Drive ────────────────────────`n" -ForegroundColor Cyan
    $user     = Read-RequiredInput "Username (SAM account)"
    $computer = Read-OptionalInput "Remote computer name (blank = local)" ""
    $letter   = Read-OptionalInput "Drive letter" "Z"
    $unc      = Read-OptionalInput "UNC path" "\\DC01\CompanyShare"
    $ticket   = Read-OptionalInput "Ticket number" ""

    $remoteArgs = @{}
    if ($computer) { $remoteArgs = @{ RemoteComputer = $computer } }

    & "$PSScriptRoot\05-map-drive.ps1" `
        -Username $user -DriveLetter $letter -UNCPath $unc `
        -TicketNumber $ticket @remoteArgs
}

function Show-RecentLog {
    Write-Host "`n  ── Recent Helpdesk Log (last 40 lines) ──────`n" -ForegroundColor Cyan
    if (Test-Path $script:LogFile) {
        Get-Content $script:LogFile -Tail 40 | ForEach-Object {
            $color = switch -Regex ($_) {
                "\[OK\]"     { "Green" }
                "\[WARN\]"   { "Yellow" }
                "\[ERROR\]"  { "Red" }
                "\[ACTION\]" { "Magenta" }
                default      { "Gray" }
            }
            Write-Host "  $_" -ForegroundColor $color
        }
    } else {
        Write-Host "  No log file found at: $($script:LogFile)" -ForegroundColor Yellow
    }
}

function Invoke-UserLookup {
    Write-Host "`n  ── Quick AD User Lookup ─────────────────────`n" -ForegroundColor Cyan
    $query = Read-RequiredInput "Username, display name, or email (partial OK)"

    $results = Get-ADUser -Filter {
        SamAccountName -like $('*' + $query + '*') -or
        DisplayName -like $('*' + $query + '*') -or
        EmailAddress -like $('*' + $query + '*')
    } -Properties Department, Title, Enabled, LockedOut, LastLogonDate, EmailAddress |
    Sort-Object Name

    if (-not $results) {
        Write-Host "  No users found matching: $query" -ForegroundColor Yellow
        return
    }

    Write-Host "  Found $($results.Count) user(s):`n" -ForegroundColor Green
    $results | ForEach-Object {
        $statusColor = if ($_.Enabled -and -not $_.LockedOut) { "Green" } else { "Red" }
        $statusText  = @()
        if (-not $_.Enabled)  { $statusText += "DISABLED" }
        if ($_.LockedOut)     { $statusText += "LOCKED" }
        if (-not $statusText) { $statusText += "Active" }

        Write-Host ("  {0,-28} {1,-12} {2,-24} {3}" -f `
            $_.Name, $_.SamAccountName, $_.Department, ($statusText -join ",")) `
            -ForegroundColor $statusColor
    }
    Write-Host ""
}

function Show-GroupList {
    Write-Host "`n  ── AD Security Groups ───────────────────────`n" -ForegroundColor Cyan
    $filter = Read-OptionalInput "Filter by name (blank = show all CorpTech groups)" "GRP-"

    Get-ADGroup -Filter "Name -like '$("*$filter*")'" |
    Sort-Object Name |
    ForEach-Object {
        $memberCount = (Get-ADGroupMember -Identity $_.Name -ErrorAction SilentlyContinue).Count
        Write-Host ("  {0,-36} {1,3} members" -f $_.Name, $memberCount) -ForegroundColor White
    }
    Write-Host ""
}

function Test-DomainHealth {
    Write-Host "`n  ── Domain Health Check ──────────────────────`n" -ForegroundColor Cyan

    # DC reachability
    $dc = (Get-ADDomainController).HostName
    $ping = Test-Connection -ComputerName $dc -Count 1 -Quiet -ErrorAction SilentlyContinue
    Write-Host ("  [{0}] DC01 ({1}) reachable" -f $(if ($ping){"OK  "}else{"FAIL"}), $dc) `
        -ForegroundColor $(if ($ping){"Green"}else{"Red"})

    # AD Web Services
    try {
        $domain = Get-ADDomain -ErrorAction Stop
        Write-Host "  [OK  ] AD Web Services responding — Domain: $($domain.DNSRoot)" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] AD Web Services not responding" -ForegroundColor Red
    }

    # DNS
    try {
        $dns = Resolve-DnsName "corp.local" -Type SOA -ErrorAction Stop
        Write-Host "  [OK  ] DNS resolving corp.local" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] DNS resolution for corp.local failed" -ForegroundColor Red
    }

    # Sysvol / Netlogon shares
    $sysvol  = Test-Path "\\corp.local\SYSVOL" -ErrorAction SilentlyContinue
    $netlogon = Test-Path "\\corp.local\NETLOGON" -ErrorAction SilentlyContinue
    Write-Host ("  [{0}] SYSVOL share accessible" -f $(if ($sysvol){"OK  "}else{"FAIL"})) `
        -ForegroundColor $(if ($sysvol){"Green"}else{"Red"})
    Write-Host ("  [{0}] NETLOGON share accessible" -f $(if ($netlogon){"OK  "}else{"FAIL"})) `
        -ForegroundColor $(if ($netlogon){"Green"}else{"Red"})

    # FSMO roles
    try {
        $fsmo = netdom query fsmo 2>&1
        Write-Host "  [OK  ] FSMO role check completed (see output below)" -ForegroundColor Green
        $fsmo | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    } catch {
        Write-Host "  [WARN] Could not query FSMO roles" -ForegroundColor Yellow
    }

    Write-Host ""
}

# ── Main loop ─────────────────────────────────────────────────
Show-Splash

while ($true) {
    Show-Menu
    $choice = Read-Host "  Enter selection"
    Write-Host ""

    switch ($choice.Trim().ToUpper()) {
        "1" { Invoke-PasswordReset }
        "2" { Invoke-AccountUnlock }
        "3" { Invoke-GroupChange }
        "4" { Invoke-Offboarding }
        "5" { Invoke-DriveMap }
        "6" { Show-RecentLog }
        "7" { Invoke-UserLookup }
        "8" { Show-GroupList }
        "9" { Test-DomainHealth }
        "Q" {
            Write-Host "  Goodbye. Session log: $($script:LogFile)`n" -ForegroundColor DarkGray
            exit 0
        }
        default {
            Write-Host "  Invalid selection. Enter 1-9 or Q." -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Read-Host "  Press Enter to return to menu"
    Show-Splash
}
