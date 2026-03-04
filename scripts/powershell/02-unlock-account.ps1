#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Helpdesk Task 2 — Unlock a locked AD user account.
    Also pulls the lockout source from the DC's Security event log
    so you can identify and fix the root cause (bad saved credential,
    misconfigured service, mobile device sync, etc.)

.PARAMETER Username
    The SAM account name of the locked user (e.g. kthompson)

.PARAMETER TicketNumber
    The associated osTicket number.

.PARAMETER SkipEventLog
    Skip the event log lookup (faster, but no root cause info).

.EXAMPLE
    .\02-unlock-account.ps1 -Username kthompson -TicketNumber 100002
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Username,

    [string]$TicketNumber = "",

    [switch]$SkipEventLog
)

. "$PSScriptRoot\00-helpdesk-common.ps1"
Assert-ADModule

$script:TicketNumber = $TicketNumber

Write-Banner -Title "Account Unlock" -Ticket $TicketNumber

# ── Step 1: Look up user ──────────────────────────────────────
Write-HDLog "Looking up user: $Username"
$user = Get-ValidatedADUser -Username $Username
if (-not $user) { exit 1 }

Show-UserSummary -User $user

# ── Step 2: Check actual lock state ──────────────────────────
if (-not $user.LockedOut) {
    Write-HDLog "Account '$($user.SamAccountName)' is NOT currently locked." "WARN"
    Write-Host ""
    Write-Host "  Account is not locked. Nothing to do." -ForegroundColor Yellow
    Write-Host "  If the user still cannot log in, check:" -ForegroundColor DarkGray
    Write-Host "    - Is the account disabled?   $(if (-not $user.Enabled){'YES — run 04-offboard to re-enable'}else{'No'})" -ForegroundColor DarkGray
    Write-Host "    - Is the password expired?   $(if ($user.PasswordExpired){'YES — run 01-reset-password'}else{'No'})" -ForegroundColor DarkGray
    Write-Host "    - Are they on the right domain? (CORP\username vs local admin)" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

# ── Step 3: Pull lockout source from Security event log ───────
if (-not $SkipEventLog) {
    Write-HDLog "Searching Security event log for lockout source (Event 4740)..."
    Write-Host ""
    Write-Host "  ── Lockout Source Investigation ─────────────" -ForegroundColor DarkGray

    try {
        # Event 4740 is logged on the PDC Emulator
        $pdc = (Get-ADDomain).PDCEmulator

        $filterXml = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">
      *[System[EventID=4740] and EventData[Data[@Name='TargetUserName']='$Username']]
    </Select>
  </Query>
</QueryList>
"@
        $lockoutEvents = Get-WinEvent -ComputerName $pdc `
            -FilterXml $filterXml -MaxEvents 10 -ErrorAction Stop

        if ($lockoutEvents) {
            Write-Host "  Found $($lockoutEvents.Count) recent lockout event(s):" -ForegroundColor Cyan
            Write-Host ""

            foreach ($evt in $lockoutEvents) {
                $xml        = [xml]$evt.ToXml()
                $sourceHost = ($xml.Event.EventData.Data |
                               Where-Object { $_.Name -eq "CallerComputerName" }).'#text'
                $evtTime    = $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")

                Write-Host ("  {0}  →  Source: {1}" -f $evtTime,
                    $(if ($sourceHost) { $sourceHost } else { "(blank — Kerberos or network logon)" })) -ForegroundColor White

                Write-HDLog "Lockout event at $evtTime from '$sourceHost'" "INFO"
            }

            $latestSource = ($xml.Event.EventData.Data |
                             Where-Object { $_.Name -eq "CallerComputerName" }).'#text'

            Write-Host ""
            Write-Host "  ── Common root causes by source ─────────────" -ForegroundColor DarkGray
            if ($latestSource -match "^\s*$" -or -not $latestSource) {
                Write-Host "  Source is blank → usually a mobile device (phone/tablet) or" -ForegroundColor Yellow
                Write-Host "  Outlook Web Access / Kerberos pre-auth failure." -ForegroundColor Yellow
                Write-Host "  Ask the user to update their phone's email password." -ForegroundColor Yellow
            } elseif ($latestSource -match "^(DC|SRV|SERVER)") {
                Write-Host "  Source is a server → likely a saved credential in a service," -ForegroundColor Yellow
                Write-Host "  scheduled task, or IIS app pool using this account." -ForegroundColor Yellow
                Write-Host "  Check services on: $latestSource" -ForegroundColor Yellow
            } else {
                Write-Host "  Source is workstation: $latestSource" -ForegroundColor Yellow
                Write-Host "  Likely cause: saved Windows credential with old password." -ForegroundColor Yellow
                Write-Host "  Fix: On $latestSource → Credential Manager → clear corp.local entries." -ForegroundColor Yellow
            }
        } else {
            Write-Host "  No Event 4740 records found in the last 10 events." -ForegroundColor DarkGray
            Write-Host "  The event may have rolled out of the log, or auditing is not enabled." -ForegroundColor DarkGray
        }
    } catch {
        Write-HDLog "Could not query Security event log on PDC: $($_.Exception.Message)" "WARN"
        Write-Host "  (Event log lookup failed — proceeding with unlock)" -ForegroundColor DarkGray
    }

    Write-Host ""
}

# ── Step 4: Confirm before unlocking ─────────────────────────
if (-not (Confirm-Action "Unlock account '$($user.SamAccountName)' ($($user.Name))?")) {
    Write-HDLog "Unlock cancelled by agent." "WARN"
    exit 0
}

# ── Step 5: Unlock ────────────────────────────────────────────
try {
    if ($PSCmdlet.ShouldProcess($user.SamAccountName, "Unlock-ADAccount")) {
        Unlock-ADAccount -Identity $user.SamAccountName -ErrorAction Stop
        Write-HDLog "Account unlocked successfully: $($user.SamAccountName)" "OK"
    }
} catch {
    Write-HDLog "Unlock FAILED: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ── Step 6: Verify ────────────────────────────────────────────
Start-Sleep -Seconds 1
$refreshed = Get-ADUser -Identity $user.SamAccountName -Properties LockedOut
if (-not $refreshed.LockedOut) {
    Write-HDLog "Verified: account is no longer locked" "OK"
} else {
    Write-HDLog "Account still shows locked after unlock attempt — replication lag possible" "WARN"
}

# ── Step 7: Log ───────────────────────────────────────────────
Write-HDLog "ACTION: Account unlocked | User=$($user.SamAccountName) | Dept=$($user.Department)" "ACTION"

# ── Summary ───────────────────────────────────────────────────
Write-Host ""
Write-Host "  ── Unlock Complete ─────────────────────────" -ForegroundColor DarkCyan
Write-Result "User"         $user.Name              "Green"
Write-Result "Username"     $user.SamAccountName    "Green"
Write-Result "Lock State"   "UNLOCKED"              "Green"
Write-Result "Log"          $script:LogFile         "DarkGray"
Write-Host ""
Write-Host "  Remind the user to:" -ForegroundColor DarkGray
Write-Host "    1. Clear saved passwords in Credential Manager if prompted" -ForegroundColor DarkGray
Write-Host "    2. Update password on their phone if using corporate email" -ForegroundColor DarkGray
Write-Host "    3. Contact helpdesk if locked again — indicates a deeper issue" -ForegroundColor DarkGray
Write-Host ""
