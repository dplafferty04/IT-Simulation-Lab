#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Stage 3 — Verification script. Run after stages 0-2 to confirm everything
    was created correctly. Outputs a formatted summary and flags any issues.
#>

Import-Module ActiveDirectory -ErrorAction Stop

$DomainDN = "DC=corp,DC=local"
$ErrorCount = 0

function Write-Section($title) {
    Write-Host ""
    Write-Host "── $title " -ForegroundColor Cyan -NoNewline
    Write-Host ("─" * (50 - $title.Length)) -ForegroundColor DarkGray
}
function Write-Pass($msg) { Write-Host "  [PASS] $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red; $script:ErrorCount++ }
function Write-Info($msg) { Write-Host "  [INFO] $msg" -ForegroundColor Gray }

# ── Domain ────────────────────────────────────────────────────────────────────
Write-Section "Domain"
$domain = Get-ADDomain -ErrorAction SilentlyContinue
if ($domain) {
    Write-Pass "Domain: $($domain.DNSRoot)"
    Write-Pass "Forest: $($domain.Forest)"
    Write-Pass "DC: $($domain.PDCEmulator)"
    Write-Info "Functional Level: $($domain.DomainMode)"
} else {
    Write-Fail "Could not retrieve domain information"
}

# ── OUs ───────────────────────────────────────────────────────────────────────
Write-Section "Organizational Units"
$expectedOUs = @("CorpUsers","IT","HR","Finance","Computers","Servers","ServiceAccts")
foreach ($ou in $expectedOUs) {
    $found = Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -ErrorAction SilentlyContinue
    if ($found) { Write-Pass "OU exists: $ou" }
    else         { Write-Fail "OU MISSING: $ou" }
}

# ── Users ─────────────────────────────────────────────────────────────────────
Write-Section "User Accounts (10 expected)"
$expectedUsers = @("jsmith","alopez","mchen","swilliams","djohnson","rpatel","kthompson","bwashington","lmartinez","tnguyen")
foreach ($sam in $expectedUsers) {
    $u = Get-ADUser -Filter "SamAccountName -eq '$sam'" -Properties Department,Title,Enabled -ErrorAction SilentlyContinue
    if ($u) {
        $status = if ($u.Enabled) { "Enabled" } else { "DISABLED" }
        Write-Pass "$sam | $($u.Title) | $($u.Department) | $status"
    } else {
        Write-Fail "User MISSING: $sam"
    }
}

# ── Groups ────────────────────────────────────────────────────────────────────
Write-Section "Security Groups"
$expectedGroups = @("GRP-IT-Admins","GRP-IT-HelpDesk","GRP-HR-Staff","GRP-Finance-Staff","GRP-VPN-Users","GRP-SharedDrive-RW","GRP-SharedDrive-RO")
foreach ($grp in $expectedGroups) {
    $g = Get-ADGroup -Filter "Name -eq '$grp'" -ErrorAction SilentlyContinue
    if ($g) {
        $members = (Get-ADGroupMember -Identity $grp -ErrorAction SilentlyContinue).Count
        Write-Pass "$grp ($members members)"
    } else {
        Write-Fail "Group MISSING: $grp"
    }
}

# ── GPOs ──────────────────────────────────────────────────────────────────────
Write-Section "Group Policy Objects"
$expectedGPOs = @("CORP-Password-Policy","CORP-Login-Banner","CORP-USB-Restriction","CORP-Drive-Map")
foreach ($gpoName in $expectedGPOs) {
    $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
    if ($gpo) {
        Write-Pass "$gpoName (Status: $($gpo.GpoStatus))"
    } else {
        Write-Fail "GPO MISSING: $gpoName"
    }
}

# ── SMB Share ─────────────────────────────────────────────────────────────────
Write-Section "SMB Share"
$share = Get-SmbShare -Name "CompanyShare" -ErrorAction SilentlyContinue
if ($share) {
    Write-Pass "\\DC01\CompanyShare exists at: $($share.Path)"
    Get-SmbShareAccess -Name "CompanyShare" | ForEach-Object {
        Write-Info "  $($_.AccountName) — $($_.AccessRight)"
    }
} else {
    Write-Fail "SMB share CompanyShare not found"
}

# ── DNS ───────────────────────────────────────────────────────────────────────
Write-Section "DNS Check"
try {
    $dnsResult = Resolve-DnsName -Name "corp.local" -Type SOA -ErrorAction Stop
    Write-Pass "DNS resolving corp.local successfully"
} catch {
    Write-Fail "DNS resolution for corp.local failed: $_"
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "══════════════════════════════════════════════" -ForegroundColor DarkCyan
if ($ErrorCount -eq 0) {
    Write-Host "  ALL CHECKS PASSED — AD configured correctly" -ForegroundColor Green
} else {
    Write-Host "  $ErrorCount CHECK(S) FAILED — review output above" -ForegroundColor Red
}
Write-Host "══════════════════════════════════════════════" -ForegroundColor DarkCyan

# ── Quick Reference Card ──────────────────────────────────────────────────────
Write-Host @"

QUICK REFERENCE — corp.local
  Domain Admin:  CORP\Administrator
  User password: Welc0me!2024  (must change at first logon)
  Share:         \\DC01\CompanyShare (mapped as Z: via GPO)
  RSAT:          Server Manager > Tools > AD Users & Computers

  Useful commands:
    gpupdate /force                     Force policy refresh on client
    gpresult /h C:\gpo-report.html      Generate GPO report (open in browser)
    Get-ADUser -Filter * | Select Name  List all users
    Test-ComputerSecureChannel -Repair  Fix domain trust issues on clients
"@ -ForegroundColor DarkGray
