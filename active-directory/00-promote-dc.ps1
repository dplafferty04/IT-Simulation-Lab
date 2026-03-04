#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Stage 0 — Install ADDS role and promote server to Domain Controller.
    Run this FIRST on a fresh Windows Server VM before any other AD scripts.

.NOTES
    - Tested on Windows Server 2022 (Desktop Experience)
    - VM must have a STATIC IP before running this script
    - Server will REBOOT automatically when promotion completes
    - After reboot, log in as CORP\Administrator and run 01-configure-ad.ps1

.EXAMPLE
    # On the Windows Server VM, open PowerShell as Administrator:
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\00-promote-dc.ps1
#>

# ── Configuration ─────────────────────────────────────────────────────────────
$DomainName      = "corp.local"
$DomainNetBIOS   = "CORP"
$SafeModePassword = (ConvertTo-SecureString "P@ssw0rd!SafeMode2024" -AsPlainText -Force)
$DCHostname       = "DC01"
# ──────────────────────────────────────────────────────────────────────────────

function Write-Step($msg) {
    Write-Host "`n[*] $msg" -ForegroundColor Cyan
}
function Write-OK($msg) {
    Write-Host "    [OK] $msg" -ForegroundColor Green
}

# ── Step 1: Rename the computer if needed ─────────────────────────────────────
Write-Step "Checking hostname..."
if ($env:COMPUTERNAME -ne $DCHostname) {
    Write-Host "    Renaming computer to $DCHostname (reboot required after promotion)" -ForegroundColor Yellow
    Rename-Computer -NewName $DCHostname -Force -ErrorAction SilentlyContinue
    Write-OK "Hostname will be $DCHostname after reboot."
} else {
    Write-OK "Hostname already set to $DCHostname"
}

# ── Step 2: Set DNS to loopback (required before promotion) ──────────────────
Write-Step "Configuring DNS to loopback..."
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses "127.0.0.1","8.8.8.8"
Write-OK "DNS set to 127.0.0.1 (loopback) and 8.8.8.8 (fallback)"

# ── Step 3: Install Windows Features ─────────────────────────────────────────
Write-Step "Installing AD DS, DNS, and management tools..."
$features = @(
    "AD-Domain-Services",
    "DNS",
    "RSAT-ADDS",
    "RSAT-ADDS-Tools",
    "RSAT-AD-PowerShell",
    "GPMC"
)
foreach ($f in $features) {
    $result = Install-WindowsFeature -Name $f -IncludeManagementTools -ErrorAction SilentlyContinue
    if ($result.Success) {
        Write-OK "Installed: $f"
    } else {
        Write-Host "    [WARN] Feature may already be installed: $f" -ForegroundColor Yellow
    }
}

# ── Step 4: Promote to Domain Controller ─────────────────────────────────────
Write-Step "Promoting server to Domain Controller for domain: $DomainName"
Write-Host "    This will trigger an automatic REBOOT when complete." -ForegroundColor Yellow
Write-Host "    After reboot, log in as $DomainNetBIOS\Administrator" -ForegroundColor Yellow
Write-Host ""

$installParams = @{
    DomainName                    = $DomainName
    DomainNetbiosName             = $DomainNetBIOS
    DomainMode                    = "WinThreshold"   # Windows Server 2016+
    ForestMode                    = "WinThreshold"
    InstallDns                    = $true
    CreateDnsDelegation           = $false
    DatabasePath                  = "C:\Windows\NTDS"
    LogPath                       = "C:\Windows\NTDS"
    SysvolPath                    = "C:\Windows\SYSVOL"
    SafeModeAdministratorPassword = $SafeModePassword
    Force                         = $true
    NoRebootOnCompletion          = $false
}

Import-Module ADDSDeployment -ErrorAction Stop
Install-ADDSForest @installParams

# ── Note: Execution stops here — server reboots ───────────────────────────────
