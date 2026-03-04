#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Helpdesk Task 5 — Map a network drive for a local or remote user.
    Supports: mapping locally, mapping on a remote machine via Invoke-Command,
    and verifying an existing GPO-mapped drive is working correctly.

.PARAMETER Username
    The local username to map the drive for (when running locally on their machine).

.PARAMETER RemoteComputer
    If specified, connects to this machine via WinRM and maps the drive there.
    Leave blank to map on the current machine.

.PARAMETER DriveLetter
    Drive letter to map (e.g. Z). Default: Z

.PARAMETER UNCPath
    The network path to map (e.g. \\DC01\CompanyShare).
    Default: \\DC01\CompanyShare (CorpTech standard share)

.PARAMETER DriveLabel
    Friendly label shown in Explorer. Default: "Company Share"

.PARAMETER Persistent
    Whether the mapping survives logoff. Default: $true

.PARAMETER TicketNumber
    The associated osTicket number.

.PARAMETER Verify
    Only verify if the drive is mapped and accessible — do not map.

.EXAMPLE
    # Map on the current workstation for the logged-in user
    .\05-map-drive.ps1 -Username kthompson -TicketNumber 100018

.EXAMPLE
    # Map on a remote machine
    .\05-map-drive.ps1 -Username bwashington -RemoteComputer "Finance-WS-05" -TicketNumber 100019

.EXAMPLE
    # Map a custom path with a custom letter
    .\05-map-drive.ps1 -Username rpatel -DriveLetter "Y" -UNCPath "\\DC01\CompanyShare\Finance" -DriveLabel "Finance Drive"

.EXAMPLE
    # Verify only
    .\05-map-drive.ps1 -Username kthompson -Verify
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Username,

    [string]$RemoteComputer = "",

    [ValidatePattern("^[A-Za-z]$")]
    [string]$DriveLetter = "Z",

    [string]$UNCPath = "\\DC01\CompanyShare",

    [string]$DriveLabel = "Company Share",

    [bool]$Persistent = $true,

    [string]$TicketNumber = "",

    [switch]$Verify
)

. "$PSScriptRoot\00-helpdesk-common.ps1"
Assert-ADModule

$script:TicketNumber = $TicketNumber
$DriveLetter = $DriveLetter.ToUpper()
$mappingTarget = if ($RemoteComputer) { $RemoteComputer } else { "Local ($env:COMPUTERNAME)" }

Write-Banner -Title $(if ($Verify) {"Drive Map Verification"} else {"Map Network Drive"}) `
             -Ticket $TicketNumber

# ── Step 1: Validate AD user ─────────────────────────────────
Write-HDLog "Looking up user: $Username"
$user = Get-ValidatedADUser -Username $Username
if (-not $user) { exit 1 }

if (-not $user.Enabled) {
    Write-HDLog "Account is disabled — drive mapping will fail at logon." "WARN"
}

Write-Result "User"           $user.Name
Write-Result "Username"       $user.SamAccountName
Write-Result "UNC Path"       $UNCPath
Write-Result "Drive Letter"   "${DriveLetter}:"
Write-Result "Label"          $DriveLabel
Write-Result "Target Machine" $mappingTarget
Write-Result "Persistent"     $Persistent
Write-Host ""

# ── Step 2: Test UNC path connectivity ───────────────────────
Write-HDLog "Testing connectivity to: $UNCPath"
$serverName = ($UNCPath -split "\\")[2]
$pingResult = Test-Connection -ComputerName $serverName -Count 1 -Quiet -ErrorAction SilentlyContinue

if (-not $pingResult) {
    Write-HDLog "Cannot reach $serverName — check DNS, firewall, or SMB service" "ERROR"
    Write-Host ""
    Write-Host "  Troubleshooting steps:" -ForegroundColor Yellow
    Write-Host "    ping $serverName" -ForegroundColor DarkGray
    Write-Host "    Test-NetConnection $serverName -Port 445" -ForegroundColor DarkGray
    Write-Host "    Get-SmbShare -CimSession $serverName" -ForegroundColor DarkGray
    exit 1
} else {
    Write-HDLog "Server $serverName is reachable (ping OK)" "OK"
}

# Test SMB port (445)
$smbTest = Test-NetConnection -ComputerName $serverName -Port 445 -WarningAction SilentlyContinue
if (-not $smbTest.TcpTestSucceeded) {
    Write-HDLog "Port 445 (SMB) is not reachable on $serverName — firewall may be blocking" "ERROR"
    exit 1
} else {
    Write-HDLog "SMB port 445 is open on $serverName" "OK"
}

# ── The mapping logic block ───────────────────────────────────
# This scriptblock can run locally or be sent via Invoke-Command
$mappingBlock = {
    param($Username, $DriveLetter, $UNCPath, $DriveLabel, $Persistent, $Verify)

    $results = @()

    # Get the user's SID for per-user drive mapping in the registry
    try {
        $adUser  = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity(
            [System.DirectoryServices.AccountManagement.PrincipalContext]::new("Domain"),
            $Username
        )
        $userSID = $adUser.Sid.ToString()
    } catch {
        $userSID = $null
    }

    # Check if drive is already mapped
    $existingDrive = Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue
    if ($existingDrive) {
        $results += "[EXISTS] ${DriveLetter}: is already mapped to: $($existingDrive.Root)"
        if ($Verify) { return $results }

        # Remove existing mapping first to allow remapping
        try {
            Remove-PSDrive -Name $DriveLetter -Force -ErrorAction Stop
            $results += "[OK] Removed existing drive mapping for ${DriveLetter}:"
        } catch {
            # Try net use
            & net use "${DriveLetter}:" /delete /y 2>&1 | Out-Null
            $results += "[OK] Removed via net use"
        }
    } elseif ($Verify) {
        $results += "[MISSING] ${DriveLetter}: is not currently mapped"

        # Check if UNC is accessible anyway
        if (Test-Path $UNCPath) {
            $results += "[OK] UNC path $UNCPath IS accessible from this machine"
        } else {
            $results += "[FAIL] UNC path $UNCPath is NOT accessible"
        }
        return $results
    }

    if ($Verify) { return $results }

    # ── Map the drive ──────────────────────────────────────────
    try {
        $persistStr = if ($Persistent) { "/PERSISTENT:YES" } else { "/PERSISTENT:NO" }

        # Use net use for reliability (works in all contexts, not just PS session)
        $netResult = & net use "${DriveLetter}:" "$UNCPath" $persistStr /y 2>&1
        if ($LASTEXITCODE -eq 0) {
            $results += "[OK] Drive mapped via net use: ${DriveLetter}: → $UNCPath"
        } else {
            $results += "[WARN] net use exit code $LASTEXITCODE : $netResult"
            # Fallback: New-PSDrive
            New-PSDrive -Name $DriveLetter -PSProvider FileSystem `
                -Root $UNCPath -Persist:$Persistent -Scope Global -ErrorAction Stop | Out-Null
            $results += "[OK] Drive mapped via New-PSDrive (fallback)"
        }
    } catch {
        $results += "[FAIL] Mapping failed: $($_.Exception.Message)"
        return $results
    }

    # ── Set volume label in registry (friendly name in Explorer) ──
    if ($userSID) {
        $regPath = "HKU:\$userSID\Network\$DriveLetter"
        try {
            if (-not (Test-Path "HKU:")) {
                New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
            }
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }
            Set-ItemProperty -Path $regPath -Name "RemotePath"   -Value $UNCPath      -Force
            Set-ItemProperty -Path $regPath -Name "UserName"     -Value ""             -Force
            Set-ItemProperty -Path $regPath -Name "ProviderName" -Value "Microsoft Windows Network" -Force
            $results += "[OK] Registry drive entry written for user $Username"
        } catch {
            $results += "[WARN] Could not write user registry entry: $_"
        }
    }

    # ── Verify the mapping is accessible ──────────────────────
    if (Test-Path "${DriveLetter}:") {
        $items = (Get-ChildItem "${DriveLetter}:" -ErrorAction SilentlyContinue).Count
        $results += "[OK] Drive ${DriveLetter}: is accessible — $items item(s) visible"
    } else {
        $results += "[WARN] Drive ${DriveLetter}: not accessible after mapping"
    }

    return $results
}

# ── Step 3: Run locally or remotely ──────────────────────────
if ($RemoteComputer) {
    Write-HDLog "Connecting to $RemoteComputer via WinRM..."

    # Test WinRM
    if (-not (Test-WSMan -ComputerName $RemoteComputer -ErrorAction SilentlyContinue)) {
        Write-HDLog "WinRM not reachable on $RemoteComputer" "ERROR"
        Write-Host "  Enable WinRM on the target: Enable-PSRemoting -Force" -ForegroundColor Yellow
        Write-Host "  Or use MeshCentral terminal to run the net use command manually:" -ForegroundColor Yellow
        Write-Host "  net use ${DriveLetter}: `"$UNCPath`" /PERSISTENT:YES /y" -ForegroundColor Cyan
        exit 1
    }

    try {
        $output = Invoke-Command -ComputerName $RemoteComputer `
            -ScriptBlock $mappingBlock `
            -ArgumentList $Username, $DriveLetter, $UNCPath, $DriveLabel, $Persistent, $Verify.IsPresent `
            -ErrorAction Stop

        $output | ForEach-Object {
            $level = if ($_ -match "^\[OK\]") { "OK" } `
                     elseif ($_ -match "^\[WARN\]|^\[EXISTS\]") { "WARN" } `
                     elseif ($_ -match "^\[FAIL\]|^\[MISSING\]") { "ERROR" } `
                     else { "INFO" }
            Write-HDLog $_ $level
        }
    } catch {
        Write-HDLog "Remote execution failed: $($_.Exception.Message)" "ERROR"
        exit 1
    }
} else {
    Write-HDLog "Mapping drive locally..."
    $output = & $mappingBlock $Username $DriveLetter $UNCPath $DriveLabel $Persistent $Verify.IsPresent
    $output | ForEach-Object {
        $level = if ($_ -match "^\[OK\]") { "OK" } `
                 elseif ($_ -match "^\[WARN\]|^\[EXISTS\]") { "WARN" } `
                 elseif ($_ -match "^\[FAIL\]|^\[MISSING\]") { "ERROR" } `
                 else { "INFO" }
        Write-HDLog $_ $level
    }
}

# ── Step 4: Log action ───────────────────────────────────────
Write-HDLog "ACTION: Drive map | User=$Username | Drive=${DriveLetter}: | UNC=$UNCPath | Target=$mappingTarget | Verify=$($Verify.IsPresent)" "ACTION"

# ── Summary ───────────────────────────────────────────────────
Write-Host ""
Write-Host "  ── Summary ─────────────────────────────────" -ForegroundColor DarkCyan
Write-Result "User"        $user.Name
Write-Result "Drive"       "${DriveLetter}: → $UNCPath"   "Green"
Write-Result "Persistent"  $Persistent
Write-Result "Machine"     $mappingTarget
Write-Host ""

Write-Host "  If the drive disappears after logoff:" -ForegroundColor DarkGray
Write-Host "    1. Check GPO is applied: gpresult /r | findstr CORP-Drive-Map" -ForegroundColor DarkGray
Write-Host "    2. Force GPO refresh: gpupdate /force" -ForegroundColor DarkGray
Write-Host "    3. Verify user is in GRP-SharedDrive-RW or GRP-SharedDrive-RO" -ForegroundColor DarkGray
Write-Host ""
