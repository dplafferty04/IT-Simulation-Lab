#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Stage 1 — Create OUs, security groups, and 10 user accounts in corp.local.
    Run AFTER the DC has rebooted and you are logged in as CORP\Administrator.

.NOTES
    All users are created with password: Welc0me!2024  (must change at next logon)
    User photos and realistic attributes are set for a professional demo.
#>

Import-Module ActiveDirectory -ErrorAction Stop

# ── Configuration ─────────────────────────────────────────────────────────────
$DomainDN  = "DC=corp,DC=local"
$DomainFQDN = "corp.local"
$SharedDrivePath = "\\DC01\CompanyShare"
$DefaultPassword = ConvertTo-SecureString "Welc0me!2024" -AsPlainText -Force
# ──────────────────────────────────────────────────────────────────────────────

function Write-Step($msg) { Write-Host "`n[*] $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "    [+] $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "    [~] Already exists: $msg" -ForegroundColor DarkYellow }

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 1 — Organizational Units
# ══════════════════════════════════════════════════════════════════════════════
Write-Step "Creating Organizational Units..."

$OUs = @(
    @{ Name = "CorpUsers";    Path = $DomainDN;                   Desc = "All corporate user accounts" },
    @{ Name = "IT";           Path = "OU=CorpUsers,$DomainDN";    Desc = "Information Technology department" },
    @{ Name = "HR";           Path = "OU=CorpUsers,$DomainDN";    Desc = "Human Resources department" },
    @{ Name = "Finance";      Path = "OU=CorpUsers,$DomainDN";    Desc = "Finance and Accounting department" },
    @{ Name = "Computers";    Path = $DomainDN;                   Desc = "All managed workstations" },
    @{ Name = "Servers";      Path = $DomainDN;                   Desc = "All managed servers" },
    @{ Name = "ServiceAccts"; Path = $DomainDN;                   Desc = "Service and automation accounts" }
)

foreach ($ou in $OUs) {
    $dn = "OU=$($ou.Name),$($ou.Path)"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path -Description $ou.Desc -ProtectedFromAccidentalDeletion $true
        Write-OK "Created OU: $($ou.Name)"
    } else {
        Write-Skip $ou.Name
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 2 — Security Groups
# ══════════════════════════════════════════════════════════════════════════════
Write-Step "Creating Security Groups..."

$Groups = @(
    @{ Name = "GRP-IT-Admins";        Path = "OU=IT,OU=CorpUsers,$DomainDN";      Desc = "IT Administrators - full admin rights" },
    @{ Name = "GRP-IT-HelpDesk";      Path = "OU=IT,OU=CorpUsers,$DomainDN";      Desc = "Helpdesk technicians - limited admin rights" },
    @{ Name = "GRP-HR-Staff";         Path = "OU=HR,OU=CorpUsers,$DomainDN";      Desc = "Human Resources staff" },
    @{ Name = "GRP-Finance-Staff";    Path = "OU=Finance,OU=CorpUsers,$DomainDN"; Desc = "Finance department staff" },
    @{ Name = "GRP-VPN-Users";        Path = "OU=CorpUsers,$DomainDN";            Desc = "Users permitted VPN access" },
    @{ Name = "GRP-SharedDrive-RW";   Path = "OU=CorpUsers,$DomainDN";            Desc = "Read/Write access to CompanyShare" },
    @{ Name = "GRP-SharedDrive-RO";   Path = "OU=CorpUsers,$DomainDN";            Desc = "Read-only access to CompanyShare" }
)

foreach ($g in $Groups) {
    if (-not (Get-ADGroup -Filter "Name -eq '$($g.Name)'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $g.Name -GroupScope Global -GroupCategory Security `
                    -Path $g.Path -Description $g.Desc
        Write-OK "Created group: $($g.Name)"
    } else {
        Write-Skip $g.Name
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 3 — User Accounts
# ══════════════════════════════════════════════════════════════════════════════
Write-Step "Creating user accounts..."

# Format: SamAccountName, GivenName, Surname, Department, OU, Title, Groups, Phone, Email
$Users = @(
    @{
        Sam        = "jsmith"
        First      = "James"
        Last       = "Smith"
        Dept       = "IT"
        OU         = "OU=IT,OU=CorpUsers,$DomainDN"
        Title      = "IT Systems Administrator"
        Groups     = @("GRP-IT-Admins","GRP-VPN-Users","GRP-SharedDrive-RW")
        Phone      = "555-0101"
        Manager    = $null
    },
    @{
        Sam        = "alopez"
        First      = "Ana"
        Last       = "Lopez"
        Dept       = "IT"
        OU         = "OU=IT,OU=CorpUsers,$DomainDN"
        Title      = "Help Desk Technician"
        Groups     = @("GRP-IT-HelpDesk","GRP-VPN-Users","GRP-SharedDrive-RW")
        Phone      = "555-0102"
        Manager    = "jsmith"
    },
    @{
        Sam        = "mchen"
        First      = "Michael"
        Last       = "Chen"
        Dept       = "IT"
        OU         = "OU=IT,OU=CorpUsers,$DomainDN"
        Title      = "Network Engineer"
        Groups     = @("GRP-IT-Admins","GRP-VPN-Users","GRP-SharedDrive-RW")
        Phone      = "555-0103"
        Manager    = "jsmith"
    },
    @{
        Sam        = "swilliams"
        First      = "Sarah"
        Last       = "Williams"
        Dept       = "HR"
        OU         = "OU=HR,OU=CorpUsers,$DomainDN"
        Title      = "HR Manager"
        Groups     = @("GRP-HR-Staff","GRP-VPN-Users","GRP-SharedDrive-RW")
        Phone      = "555-0201"
        Manager    = $null
    },
    @{
        Sam        = "djohnson"
        First      = "David"
        Last       = "Johnson"
        Dept       = "HR"
        OU         = "OU=HR,OU=CorpUsers,$DomainDN"
        Title      = "HR Coordinator"
        Groups     = @("GRP-HR-Staff","GRP-SharedDrive-RO")
        Phone      = "555-0202"
        Manager    = "swilliams"
    },
    @{
        Sam        = "rpatel"
        First      = "Raj"
        Last       = "Patel"
        Dept       = "Finance"
        OU         = "OU=Finance,OU=CorpUsers,$DomainDN"
        Title      = "Finance Director"
        Groups     = @("GRP-Finance-Staff","GRP-VPN-Users","GRP-SharedDrive-RW")
        Phone      = "555-0301"
        Manager    = $null
    },
    @{
        Sam        = "kthompson"
        First      = "Karen"
        Last       = "Thompson"
        Dept       = "Finance"
        OU         = "OU=Finance,OU=CorpUsers,$DomainDN"
        Title      = "Senior Accountant"
        Groups     = @("GRP-Finance-Staff","GRP-SharedDrive-RW")
        Phone      = "555-0302"
        Manager    = "rpatel"
    },
    @{
        Sam        = "bwashington"
        First      = "Brian"
        Last       = "Washington"
        Dept       = "Finance"
        OU         = "OU=Finance,OU=CorpUsers,$DomainDN"
        Title      = "Accounts Payable Specialist"
        Groups     = @("GRP-Finance-Staff","GRP-SharedDrive-RO")
        Phone      = "555-0303"
        Manager    = "rpatel"
    },
    @{
        Sam        = "lmartinez"
        First      = "Laura"
        Last       = "Martinez"
        Dept       = "HR"
        OU         = "OU=HR,OU=CorpUsers,$DomainDN"
        Title      = "Talent Acquisition Specialist"
        Groups     = @("GRP-HR-Staff","GRP-SharedDrive-RO")
        Phone      = "555-0203"
        Manager    = "swilliams"
    },
    @{
        Sam        = "tnguyen"
        First      = "Tommy"
        Last       = "Nguyen"
        Dept       = "IT"
        OU         = "OU=IT,OU=CorpUsers,$DomainDN"
        Title      = "Help Desk Technician"
        Groups     = @("GRP-IT-HelpDesk","GRP-SharedDrive-RW")
        Phone      = "555-0104"
        Manager    = "jsmith"
    }
)

foreach ($u in $Users) {
    $upn  = "$($u.Sam)@$DomainFQDN"
    $display = "$($u.First) $($u.Last)"

    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($u.Sam)'" -ErrorAction SilentlyContinue)) {
        $newUserParams = @{
            SamAccountName        = $u.Sam
            UserPrincipalName     = $upn
            GivenName             = $u.First
            Surname               = $u.Last
            DisplayName           = $display
            Name                  = $display
            Department            = $u.Dept
            Title                 = $u.Title
            OfficePhone           = $u.Phone
            EmailAddress          = $upn
            Company               = "CorpTech"
            City                  = "Austin"
            State                 = "TX"
            Country               = "US"
            Path                  = $u.OU
            AccountPassword       = $DefaultPassword
            ChangePasswordAtLogon = $true
            Enabled               = $true
            PasswordNeverExpires  = $false
        }
        New-ADUser @newUserParams

        # Set manager attribute (second pass — manager may not exist yet on first loop)
        Write-OK "Created user: $display ($($u.Sam)) — $($u.Title)"
    } else {
        Write-Skip "$display ($($u.Sam))"
    }
}

# ── Second pass: set manager relationships ────────────────────────────────────
Write-Step "Setting manager relationships..."
foreach ($u in $Users) {
    if ($u.Manager) {
        $mgr = Get-ADUser -Filter "SamAccountName -eq '$($u.Manager)'" -ErrorAction SilentlyContinue
        if ($mgr) {
            Set-ADUser -Identity $u.Sam -Manager $mgr
            Write-OK "$($u.Sam) reports to $($u.Manager)"
        }
    }
}

# ── Third pass: group memberships ────────────────────────────────────────────
Write-Step "Assigning group memberships..."
foreach ($u in $Users) {
    foreach ($grpName in $u.Groups) {
        $grp = Get-ADGroup -Filter "Name -eq '$grpName'" -ErrorAction SilentlyContinue
        if ($grp) {
            $isMember = Get-ADGroupMember -Identity $grpName -ErrorAction SilentlyContinue |
                        Where-Object { $_.SamAccountName -eq $u.Sam }
            if (-not $isMember) {
                Add-ADGroupMember -Identity $grpName -Members $u.Sam
                Write-OK "Added $($u.Sam) -> $grpName"
            }
        } else {
            Write-Host "    [WARN] Group not found: $grpName" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n[✓] Stage 1 complete — OUs, Groups, and Users created successfully." -ForegroundColor Green
Write-Host "    Next: run 02-gpo-policies.ps1 to apply Group Policies." -ForegroundColor Cyan
