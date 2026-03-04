#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Stage 2 — Create and link Group Policy Objects.

    GPOs created:
      1. CORP-Password-Policy      → Default Domain Policy override (password rules)
      2. CORP-Login-Banner         → Legal notice on logon screen
      3. CORP-USB-Restriction      → Block removable storage (USB drives)
      4. CORP-Drive-Map            → Map \\DC01\CompanyShare as Z: drive

    Run AFTER 01-configure-ad.ps1.
#>

Import-Module GroupPolicy    -ErrorAction Stop
Import-Module ActiveDirectory -ErrorAction Stop

$DomainDN   = "DC=corp,DC=local"
$DomainFQDN = "corp.local"
$DomainName = "corp.local"

function Write-Step($msg) { Write-Host "`n[*] $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "    [+] $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "    [~] Skipped (already exists): $msg" -ForegroundColor DarkYellow }

# Helper: create GPO only if it doesn't exist
function New-GPOIfAbsent {
    param([string]$Name, [string]$Comment)
    $existing = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Skip $Name
        return $existing
    }
    $gpo = New-GPO -Name $Name -Comment $Comment -Domain $DomainFQDN
    Write-OK "Created GPO: $Name"
    return $gpo
}

# ══════════════════════════════════════════════════════════════════════════════
# GPO 1 — PASSWORD POLICY
# ══════════════════════════════════════════════════════════════════════════════
Write-Step "GPO 1: Password Policy..."

$pwGPO = New-GPOIfAbsent -Name "CORP-Password-Policy" `
    -Comment "Enforces corporate password complexity, length, and age requirements"

# Link to domain root so it applies to all users
$link = Get-GPInheritance -Target $DomainDN -ErrorAction SilentlyContinue
$alreadyLinked = $link.GpoLinks | Where-Object { $_.DisplayName -eq "CORP-Password-Policy" }
if (-not $alreadyLinked) {
    New-GPLink -Name "CORP-Password-Policy" -Target $DomainDN -LinkEnabled Yes -Enforced No
    Write-OK "Linked CORP-Password-Policy to domain root"
}

# Set password policy via registry-based GPO settings
# These map to Computer Config > Windows Settings > Security Settings > Account Policies
$pwGPOId = $pwGPO.Id

# Use secedit-style settings via GPO registry keys under MACHINE
$pwSettings = @{
    "MinimumPasswordLength"     = 14     # 14 characters minimum
    "PasswordComplexity"        = 1      # Enabled
    "MaximumPasswordAge"        = 90     # Days
    "MinimumPasswordAge"        = 1      # Prevent instant re-use cycling
    "PasswordHistorySize"       = 24     # Remember last 24 passwords
    "LockoutBadCount"           = 5      # Lock after 5 bad attempts
    "LockoutDuration"           = 30     # Lock for 30 minutes
    "ResetLockoutCount"         = 30     # Reset counter after 30 minutes
}

foreach ($setting in $pwSettings.GetEnumerator()) {
    Set-GPRegistryValue -Name "CORP-Password-Policy" `
        -Key "HKLM\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" `
        -ValueName $setting.Key -Type DWord -Value $setting.Value `
        -ErrorAction SilentlyContinue | Out-Null
}

# The canonical way to set password policy is via secedit template — generate one
$seceditTemplate = @"
[Unicode]
Unicode=yes
[System Access]
MinimumPasswordLength = 14
PasswordComplexity = 1
MaximumPasswordAge = 90
MinimumPasswordAge = 1
PasswordHistorySize = 24
LockoutBadCount = 5
ResetLockoutCount = 30
LockoutDuration = 30
[Version]
signature=`"`$CHICAGO`$`"
Revision=1
"@

$templatePath = "$env:TEMP\corp-password-policy.inf"
$seceditTemplate | Out-File -FilePath $templatePath -Encoding Unicode -Force

# Apply to Default Domain Policy via secedit (affects domain-level password policy)
secedit /configure /db "$env:TEMP\secedit.sdb" /cfg $templatePath /quiet
Write-OK "Applied password policy via secedit (domain-level account policy)"

# ══════════════════════════════════════════════════════════════════════════════
# GPO 2 — LOGIN BANNER (Legal Notice)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step "GPO 2: Login Banner..."

$bannerGPO = New-GPOIfAbsent -Name "CORP-Login-Banner" `
    -Comment "Displays legal notice and acceptable use policy on the logon screen"

$bannerTitle = "AUTHORIZED USE ONLY — CorpTech Information Systems"
$bannerText  = @"
This system is the property of CorpTech and is for authorized use only.
By logging in, you acknowledge that:

  1. All activity on this system may be monitored and recorded.
  2. Unauthorized access or use is strictly prohibited and may be prosecuted.
  3. You are bound by CorpTech's Acceptable Use Policy (AUP).
  4. You have no expectation of privacy when using CorpTech systems.

If you are not an authorized user, disconnect immediately.
Report security concerns to: it-security@corp.local | Ext. 5911
"@

Set-GPRegistryValue -Name "CORP-Login-Banner" `
    -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "legalnoticecaption" -Type String -Value $bannerTitle
Write-OK "Set banner title"

Set-GPRegistryValue -Name "CORP-Login-Banner" `
    -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "legalnoticetext" -Type String -Value $bannerText
Write-OK "Set banner text"

# Link to domain root
$alreadyLinked = (Get-GPInheritance -Target $DomainDN).GpoLinks |
                  Where-Object { $_.DisplayName -eq "CORP-Login-Banner" }
if (-not $alreadyLinked) {
    New-GPLink -Name "CORP-Login-Banner" -Target $DomainDN -LinkEnabled Yes
    Write-OK "Linked CORP-Login-Banner to domain root"
}

# ══════════════════════════════════════════════════════════════════════════════
# GPO 3 — USB / REMOVABLE STORAGE RESTRICTION
# ══════════════════════════════════════════════════════════════════════════════
Write-Step "GPO 3: USB / Removable Storage Restriction..."

$usbGPO = New-GPOIfAbsent -Name "CORP-USB-Restriction" `
    -Comment "Denies read and write access to removable storage devices (USB drives)"

# Computer Config > Admin Templates > System > Removable Storage Access
$usbKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices"

# Block all removable storage classes
$storageClasses = @(
    @{ Sub = "{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}"; Name = "Removable Disks (generic)" },
    @{ Sub = "{53f56307-b6bf-11d0-94f2-00a0c91efb8b}"; Name = "USB Mass Storage" },
    @{ Sub = "Custom\Deny_All";                          Name = "All Removable Storage" }
)

# Deny_All key — simplest blanket block
Set-GPRegistryValue -Name "CORP-USB-Restriction" `
    -Key "$usbKey\Custom" `
    -ValueName "Deny_All" -Type DWord -Value 1
Write-OK "Set Deny_All removable storage"

# Individual class denials for belt-and-suspenders coverage
foreach ($class in @("{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}", "{53f56307-b6bf-11d0-94f2-00a0c91efb8b}")) {
    Set-GPRegistryValue -Name "CORP-USB-Restriction" `
        -Key "$usbKey\$class" `
        -ValueName "Deny_Read"  -Type DWord -Value 1
    Set-GPRegistryValue -Name "CORP-USB-Restriction" `
        -Key "$usbKey\$class" `
        -ValueName "Deny_Write" -Type DWord -Value 1
}
Write-OK "Set per-class read/write deny on USB storage GUIDs"

# Also disable autorun
Set-GPRegistryValue -Name "CORP-USB-Restriction" `
    -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
    -ValueName "NoDriveTypeAutoRun" -Type DWord -Value 255
Write-OK "Disabled AutoRun on all drive types"

# Link to OU=Computers (workstations only — spare servers)
$alreadyLinked = (Get-GPInheritance -Target "OU=Computers,$DomainDN" -ErrorAction SilentlyContinue).GpoLinks |
                  Where-Object { $_.DisplayName -eq "CORP-USB-Restriction" }
if (-not $alreadyLinked) {
    New-GPLink -Name "CORP-USB-Restriction" -Target "OU=Computers,$DomainDN" -LinkEnabled Yes
    Write-OK "Linked CORP-USB-Restriction to OU=Computers"
}

# ══════════════════════════════════════════════════════════════════════════════
# GPO 4 — DRIVE MAP (Map \\DC01\CompanyShare as Z:)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step "GPO 4: Network Drive Mapping..."

# First ensure the share exists
$sharePath = "C:\CompanyShare"
if (-not (Test-Path $sharePath)) {
    New-Item -ItemType Directory -Path $sharePath -Force | Out-Null

    # Create department subdirectories
    @("IT","HR","Finance","Public") | ForEach-Object {
        New-Item -ItemType Directory -Path "$sharePath\$_" -Force | Out-Null
    }
    Write-OK "Created share directory structure at $sharePath"
}

# Create the SMB share if it doesn't exist
$smbShare = Get-SmbShare -Name "CompanyShare" -ErrorAction SilentlyContinue
if (-not $smbShare) {
    New-SmbShare -Name "CompanyShare" -Path $sharePath `
        -Description "CorpTech Shared Company Drive" `
        -FullAccess "CORP\GRP-IT-Admins" `
        -ChangeAccess "CORP\GRP-SharedDrive-RW" `
        -ReadAccess "CORP\GRP-SharedDrive-RO" `
        -FolderEnumerationMode "AccessBased"   # Users only see folders they can access
    Write-OK "Created SMB share: \\DC01\CompanyShare"
} else {
    Write-Skip "SMB share CompanyShare already exists"
}

# Set NTFS permissions
$acl = Get-Acl $sharePath
$acl.SetAccessRuleProtection($true, $false)  # Break inheritance

$permissionSets = @(
    @{ Identity = "CORP\Domain Admins";      Rights = "FullControl"; Type = "Allow" },
    @{ Identity = "CORP\GRP-IT-Admins";      Rights = "FullControl"; Type = "Allow" },
    @{ Identity = "CORP\GRP-SharedDrive-RW"; Rights = "Modify";      Type = "Allow" },
    @{ Identity = "CORP\GRP-SharedDrive-RO"; Rights = "ReadAndExecute"; Type = "Allow" },
    @{ Identity = "SYSTEM";                  Rights = "FullControl"; Type = "Allow" }
)

foreach ($perm in $permissionSets) {
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $perm.Identity, $perm.Rights, "ContainerInherit,ObjectInherit", "None", $perm.Type
    )
    $acl.AddAccessRule($rule)
}
Set-Acl -Path $sharePath -AclObject $acl
Write-OK "Applied NTFS permissions to $sharePath"

# Create the Drive Map GPO using GPP (Group Policy Preferences)
$driveGPO = New-GPOIfAbsent -Name "CORP-Drive-Map" `
    -Comment "Maps \\DC01\CompanyShare as Z: drive for all domain users"

# GPP drive maps are XML stored in the GPO's User configuration
# Path: \\<SYSVOL>\<domain>\Policies\{GUID}\User\Preferences\Drives\Drives.xml
$gpoGuid   = (Get-GPO -Name "CORP-Drive-Map").Id
$gpoDrivesDir = "\\$DomainFQDN\SYSVOL\$DomainFQDN\Policies\{$gpoGuid}\User\Preferences\Drives"

if (-not (Test-Path $gpoDrivesDir)) {
    New-Item -ItemType Directory -Path $gpoDrivesDir -Force | Out-Null
}

$drivesXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Drives clsid="{8FDDCC1A-0C3C-43cd-A6B4-71A6DF20DA8C}">
  <Drive clsid="{935D1B74-9CB8-4e3c-9914-7DD559B7A417}"
         name="Z:"
         status="Z:"
         image="2"
         changed="2024-01-01 00:00:00"
         uid="{$(New-Guid)}"
         bypassErrors="1">
    <Properties action="U"
                thisDrive="SHOW"
                allDrives="NOCHANGE"
                userName=""
                path="\\DC01\CompanyShare"
                label="Company Share (Z:)"
                persistent="1"
                useLetter="1"
                letter="Z"/>
  </Drive>
</Drives>
"@

$xmlPath = "$gpoDrivesDir\Drives.xml"
$drivesXml | Out-File -FilePath $xmlPath -Encoding UTF8 -Force
Write-OK "Written GPP drive map XML to SYSVOL"

# Link drive map GPO to CorpUsers OU
$alreadyLinked = (Get-GPInheritance -Target "OU=CorpUsers,$DomainDN" -ErrorAction SilentlyContinue).GpoLinks |
                  Where-Object { $_.DisplayName -eq "CORP-Drive-Map" }
if (-not $alreadyLinked) {
    New-GPLink -Name "CORP-Drive-Map" -Target "OU=CorpUsers,$DomainDN" -LinkEnabled Yes
    Write-OK "Linked CORP-Drive-Map to OU=CorpUsers"
}

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "══════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  GPO Configuration Summary" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════" -ForegroundColor DarkCyan

$gpoSummary = @(
    [PSCustomObject]@{ GPO="CORP-Password-Policy"; Linked_To="Domain Root"; Scope="All computers/users" },
    [PSCustomObject]@{ GPO="CORP-Login-Banner";    Linked_To="Domain Root"; Scope="All computers/users" },
    [PSCustomObject]@{ GPO="CORP-USB-Restriction"; Linked_To="OU=Computers"; Scope="Workstations only" },
    [PSCustomObject]@{ GPO="CORP-Drive-Map";       Linked_To="OU=CorpUsers"; Scope="All domain users" }
)
$gpoSummary | Format-Table -AutoSize

Write-Host "Force-update clients with: gpupdate /force" -ForegroundColor Yellow
Write-Host "Verify with: gpresult /h C:\gpo-report.html" -ForegroundColor Yellow
Write-Host ""
Write-Host "[✓] Stage 2 complete — All GPOs created and linked." -ForegroundColor Green
Write-Host "    Next: run 03-create-share-dirs.ps1 or proceed to Docker setup." -ForegroundColor Cyan
