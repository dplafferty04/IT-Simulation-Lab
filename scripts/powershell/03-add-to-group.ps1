#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Helpdesk Task 3 — Add a user to an AD security group.
    Validates membership, prevents duplicates, and supports
    adding to multiple groups in one run.

.PARAMETER Username
    The SAM account name of the user.

.PARAMETER GroupName
    One or more group names to add the user to.
    Accepts partial names and tab-completes if RSAT is installed.

.PARAMETER TicketNumber
    The associated osTicket number.

.PARAMETER Remove
    If set, REMOVES the user from the group instead of adding.

.EXAMPLE
    # Add a user to one group
    .\03-add-to-group.ps1 -Username bwashington -GroupName "GRP-SharedDrive-RW" -TicketNumber 100010

.EXAMPLE
    # Add to multiple groups at once
    .\03-add-to-group.ps1 -Username mreed -GroupName "GRP-Finance-Staff","GRP-VPN-Users","GRP-SharedDrive-RW"

.EXAMPLE
    # Remove from a group
    .\03-add-to-group.ps1 -Username djohnson -GroupName "GRP-IT-Admins" -Remove
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Username,

    [Parameter(Mandatory)]
    [string[]]$GroupName,

    [string]$TicketNumber = "",

    [switch]$Remove
)

. "$PSScriptRoot\00-helpdesk-common.ps1"
Assert-ADModule

$script:TicketNumber = $TicketNumber
$action = if ($Remove) { "Remove from Group" } else { "Add to Group" }

Write-Banner -Title $action -Ticket $TicketNumber

# ── Step 1: Validate user ────────────────────────────────────
Write-HDLog "Looking up user: $Username"
$user = Get-ValidatedADUser -Username $Username
if (-not $user) { exit 1 }

Show-UserSummary -User $user

# ── Step 2: Show current group memberships ───────────────────
$currentGroups = Get-ADPrincipalGroupMembership -Identity $user.SamAccountName |
                 Select-Object -ExpandProperty Name | Sort-Object

Write-Host "  ── Current Group Memberships ($($currentGroups.Count)) ──────" -ForegroundColor DarkGray
$currentGroups | ForEach-Object { Write-Host "    • $_" -ForegroundColor DarkGray }
Write-Host ""

# ── Step 3: Process each requested group ─────────────────────
$results = @()

foreach ($grpName in $GroupName) {

    Write-Host "  ── Processing: $grpName " -ForegroundColor Cyan

    # Validate group exists
    $group = Get-ADGroup -Filter "Name -eq '$grpName'" -ErrorAction SilentlyContinue

    if (-not $group) {
        # Try a fuzzy search to suggest the right name
        $suggestions = Get-ADGroup -Filter "Name -like '*$grpName*'" -ErrorAction SilentlyContinue |
                       Select-Object -ExpandProperty Name

        Write-HDLog "Group not found: '$grpName'" "ERROR"

        if ($suggestions) {
            Write-Host "  Did you mean one of these?" -ForegroundColor Yellow
            $suggestions | ForEach-Object { Write-Host "    → $_" -ForegroundColor Yellow }
        }

        $results += [PSCustomObject]@{
            Group  = $grpName
            Action = $action
            Result = "FAILED — group not found"
        }
        continue
    }

    # Check current membership
    $isMember = $currentGroups -contains $group.Name

    if (-not $Remove) {
        # ── ADD ──────────────────────────────────────────────
        if ($isMember) {
            Write-HDLog "$($user.SamAccountName) is already a member of '$($group.Name)'" "WARN"
            $results += [PSCustomObject]@{
                Group  = $group.Name
                Action = "Add"
                Result = "Skipped — already a member"
            }
            continue
        }

        if (-not (Confirm-Action "Add '$($user.Name)' to '$($group.Name)'?")) {
            $results += [PSCustomObject]@{ Group=$group.Name; Action="Add"; Result="Cancelled" }
            continue
        }

        try {
            if ($PSCmdlet.ShouldProcess("$($user.SamAccountName) → $($group.Name)", "Add-ADGroupMember")) {
                Add-ADGroupMember -Identity $group.Name -Members $user.SamAccountName -ErrorAction Stop
                Write-HDLog "Added '$($user.SamAccountName)' to group '$($group.Name)'" "OK"
                Write-HDLog "ACTION: Group add | User=$($user.SamAccountName) | Group=$($group.Name) | Dept=$($user.Department)" "ACTION"
                $results += [PSCustomObject]@{ Group=$group.Name; Action="Add"; Result="SUCCESS" }
            }
        } catch {
            Write-HDLog "Failed to add to '$($group.Name)': $($_.Exception.Message)" "ERROR"
            $results += [PSCustomObject]@{ Group=$group.Name; Action="Add"; Result="FAILED — $($_.Exception.Message)" }
        }

    } else {
        # ── REMOVE ───────────────────────────────────────────
        if (-not $isMember) {
            Write-HDLog "$($user.SamAccountName) is not a member of '$($group.Name)' — nothing to remove" "WARN"
            $results += [PSCustomObject]@{ Group=$group.Name; Action="Remove"; Result="Skipped — not a member" }
            continue
        }

        # Safety check — warn about high-privilege groups
        if ($group.Name -match "(?i)(Domain Admin|Enterprise Admin|IT.Admin|Admin)") {
            Write-Host "  ⚠  WARNING: This is a privileged group." -ForegroundColor Red
            Write-Host "     Removing admin rights may break the user's ability to perform their job." -ForegroundColor Red
        }

        if (-not (Confirm-Action "REMOVE '$($user.Name)' FROM '$($group.Name)'?")) {
            $results += [PSCustomObject]@{ Group=$group.Name; Action="Remove"; Result="Cancelled" }
            continue
        }

        try {
            if ($PSCmdlet.ShouldProcess("$($user.SamAccountName) ← $($group.Name)", "Remove-ADGroupMember")) {
                Remove-ADGroupMember -Identity $group.Name -Members $user.SamAccountName -Confirm:$false -ErrorAction Stop
                Write-HDLog "Removed '$($user.SamAccountName)' from group '$($group.Name)'" "OK"
                Write-HDLog "ACTION: Group remove | User=$($user.SamAccountName) | Group=$($group.Name)" "ACTION"
                $results += [PSCustomObject]@{ Group=$group.Name; Action="Remove"; Result="SUCCESS" }
            }
        } catch {
            Write-HDLog "Failed to remove from '$($group.Name)': $($_.Exception.Message)" "ERROR"
            $results += [PSCustomObject]@{ Group=$group.Name; Action="Remove"; Result="FAILED — $($_.Exception.Message)" }
        }
    }
}

# ── Summary ───────────────────────────────────────────────────
Write-Host ""
Write-Host "  ── Results ──────────────────────────────────" -ForegroundColor DarkCyan
$results | ForEach-Object {
    $color = switch -Wildcard ($_.Result) {
        "SUCCESS"  { "Green" }
        "Skipped*" { "Yellow" }
        "Cancelled"{ "Yellow" }
        default    { "Red" }
    }
    Write-Host ("  {0,-32} → {1}" -f $_.Group, $_.Result) -ForegroundColor $color
}

Write-Host ""

# ── Show updated membership ───────────────────────────────────
$updatedGroups = Get-ADPrincipalGroupMembership -Identity $user.SamAccountName |
                 Select-Object -ExpandProperty Name | Sort-Object

Write-Host "  ── Updated Memberships ($($updatedGroups.Count)) ────────────" -ForegroundColor DarkGray
$updatedGroups | ForEach-Object { Write-Host "    • $_" -ForegroundColor DarkGray }
Write-Host ""

Write-Host "  Note: Group policy changes take effect at next GP refresh" -ForegroundColor DarkGray
Write-Host "  Force immediately on user's machine: gpupdate /force" -ForegroundColor DarkGray
Write-Host ""
