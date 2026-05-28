# Enterprise IT Simulation Lab — Full Deployment Guide

## What Each Component Does & Why It Exists

---

### 1. Oracle VirtualBox — The Hypervisor

**What it is:** VirtualBox is a free, open-source Type-2 hypervisor from Oracle. It runs as an application on your existing OS (Windows, macOS, or Linux) and lets you create and run virtual machines inside it.

**What it does in this lab:**
- Hosts DC01 (Windows Server 2022) and WS01 (Windows 11) as isolated virtual machines
- Provides a GUI console to each VM — no separate KVM switch or monitor needed
- Lets you snapshot VMs before destructive tests (like offboarding scripts) so you can roll back
- Manages virtual networking via Host-Only adapters — each VM gets a virtual NIC connected to a private network that only the host and other VMs on the same adapter can reach

**Why you need it:** Without a hypervisor you'd need multiple physical machines. VirtualBox lets you run the entire lab on one PC.

**Key concepts:**
- **VM** — a full virtual computer with its own CPU, RAM, and disk, completely isolated from other VMs
- **Host-Only Adapter** — a virtual network adapter that creates a private LAN between your host machine and your VMs. VMs on the same Host-Only network can talk to each other and to the host, but not to the internet (unless you add a second NAT adapter). This is how this lab replaces VLAN segmentation without needing a separate firewall VM
- **Guest Additions** — a VirtualBox driver package installed inside each VM that enables shared clipboard, drag-and-drop file transfer, and better display scaling (replaces VirtIO drivers from the Proxmox equivalent)
- **Dynamic disk** — the VM's `.vdi` disk file only uses the space actually written, not the full allocated size. A 60 GB disk might only use 15 GB on the host

---

### 2. VirtualBox Host-Only Networking — Network Segmentation

**What it is:** Instead of a pfSense firewall VM, this lab uses VirtualBox's built-in Host-Only networking to create two isolated virtual LANs. VirtualBox acts as the network fabric.

**What it does in this lab:**
- **vboxnet0 (192.168.10.0/24) — Corporate LAN**: DC01, WS01, and the Docker host all live here. VMs communicate with each other and with the host machine on this segment
- **vboxnet1 (192.168.20.0/24) — Management segment**: Splunk lives here, isolated from the corporate LAN. Splunk receives log data from DC01 via the Universal Forwarder (port 9997), but workstations can't browse to Splunk's admin UI unless you explicitly add a NAT or route
- **Static IPs** — each VM gets a manually configured static IP within its Host-Only range. DHCP from VirtualBox is disabled so IPs are predictable

**Why this approach works:** The Host-Only adapter creates true network isolation — VMs on vboxnet0 cannot reach vboxnet1 by default, mimicking VLAN segmentation in a production environment without the overhead of a firewall VM.

**Key IP assignments:**

| Host | IP | Role |
|------|-----|------|
| VirtualBox host (gateway) | 192.168.10.1 | Host gateway for Corp LAN |
| DC01 | 192.168.10.10 | AD DC, DNS server |
| WS01 | 192.168.10.20 | Domain-joined workstation |
| Docker host | 192.168.10.50 | osTicket, MeshCentral, Nginx |
| Splunk | 192.168.20.10 | SIEM |

---

### 3. Windows Server 2022 + Active Directory (DC01)

**What it is:** DC01 is a Windows Server 2022 VM promoted to be a Domain Controller. It runs Active Directory Domain Services (AD DS), which is Microsoft's implementation of LDAP + Kerberos for centralized identity management.

**What it does in this lab:**

#### Active Directory Domain Services
- Acts as the **authentication authority** for the entire `corp.local` domain. When a user logs into WS01, the workstation contacts DC01 to verify the username and password
- Stores all user accounts, groups, computers, and organizational units in a database called **NTDS.DIT**
- Runs **Kerberos** (port 88) — the ticket-based authentication protocol that lets users log in once and access network resources without re-entering their password (single sign-on)
- Runs **LDAP** (port 389/636) — the protocol that applications use to query AD for user info. osTicket could theoretically use this to authenticate helpdesk agents with their AD credentials

#### Organizational Units (OUs)
OUs are containers inside AD that organize objects. They're important because:
- **Group Policy can be applied at the OU level** — so you can give IT staff different settings than Finance staff
- They make delegation easier — you can give a junior admin rights to reset passwords only within `OU=HR` without making them a Domain Admin
- This lab has: `OU=CorpUsers` (parent) → `OU=IT`, `OU=HR`, `OU=Finance`, plus `OU=Computers`, `OU=Servers`, `OU=ServiceAccts`, `OU=Disabled`

#### Security Groups
Groups control what resources users can access:
- `GRP-IT-Admins` — members can fully administer domain resources
- `GRP-SharedDrive-RW` — members get read/write on `\\DC01\CompanyShare`
- `GRP-SharedDrive-RO` — members get read-only
- `GRP-VPN-Users` — controls who is allowed to connect via VPN on pfSense
Groups are how you implement RBAC (Role-Based Access Control) in Windows environments

#### Group Policy Objects (GPOs)
GPOs are configuration packages pushed from the DC to domain members. They apply automatically — users and computers don't need to do anything. This lab's four GPOs:

| GPO | What it actually changes on the machine |
|-----|----------------------------------------|
| CORP-Password-Policy | Writes password length/complexity rules into the domain's Security Account Manager policy. Windows enforces these when users set passwords. |
| CORP-Login-Banner | Writes a string to `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\legalnoticetext`. Windows reads this at the Ctrl+Alt+Del screen and displays it before the login form. |
| CORP-USB-Restriction | Writes DWORD values to `HKLM\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices`. The Windows storage driver reads these registry keys and blocks read/write operations on matching device classes. |
| CORP-Drive-Map | Writes an XML file (`Drives.xml`) to SYSVOL. When a user logs on, the Group Policy Client reads this XML and calls `net use` to map the drive in the user's session. |

#### DNS Server
DC01 also runs the DNS server for `corp.local`. Every workstation that joins the domain points its DNS at DC01. This is why:
- `ping dc01` works from WS01 — DC01 knows its own A record
- `\\DC01\CompanyShare` resolves — because WS01 asks DC01's DNS for the IP of DC01
- Kerberos works — Kerberos relies heavily on DNS being correct

#### SMB File Share (`\\DC01\CompanyShare`)
A Server Message Block share is the Windows native file sharing protocol. The share at `C:\CompanyShare` on DC01 is exposed as `\\DC01\CompanyShare` with:
- **Share-level permissions** — what the network allows (controlled by `New-SmbShare`)
- **NTFS permissions** — what the filesystem allows (controlled by `Set-Acl`)
- **Access-based enumeration** — users only see subdirectories they have permission to open. Finance users see `Finance\` and `Public\` but not `HR\`

---

### 4. osTicket (Docker)

**What it is:** osTicket is an open-source helpdesk ticketing system written in PHP. It's the same category of software as ServiceNow, Jira Service Management, or Zendesk — but free and self-hosted.

**What it does in this lab:**
- Provides a web portal where users submit support requests
- Organizes tickets into departments (IT Helpdesk, Network Operations) with separate queues and SLA timers
- Assigns tickets to agents and tracks status through the full lifecycle: Open → In Progress → Resolved → Closed
- Sends email notifications to users and agents at each status change
- The 15 pre-seeded tickets demonstrate realistic L1/L2 helpdesk work across account issues, hardware, software, and network categories

**How the Docker setup works:**
```
Browser → Nginx (port 8080) → osticket_app container (PHP-FPM)
                                       ↕
                              osticket_db container (MariaDB)
                              stores: tickets, users, agents, threads
```

- **MariaDB container** — stores everything: ticket data, agent accounts, message threads, configurations. Uses a named Docker volume (`osticket_db_data`) so data persists even if the container is destroyed and recreated
- **osTicket app container** — runs the PHP application. On first start it checks for the database tables; if they don't exist it shows the web installer
- **Nginx container** — acts as a reverse proxy, accepting connections on port 8080 and forwarding them to the osTicket container. This is standard practice — you never expose PHP-FPM directly

**What the seed scripts do:**
- `00-departments-sla-topics.sql` — runs `INSERT INTO ost_department`, `ost_sla`, `ost_help_topic`. Creates the configuration structure (like setting up ServiceNow categories)
- `01-staff-agents.sql` — creates agent accounts in `ost_staff` (these are the helpdesk techs who log into `/scp`) and end-user accounts in `ost_user`/`ost_user_email` (the people who submit tickets)
- `02-tickets.sql` — inserts 15 rows into `ost_ticket` (the ticket record) and corresponding rows into `ost_thread` + `ost_thread_entry` (the conversation messages). The stored procedure `seed_ticket()` wraps all of this so each ticket is created atomically

---

### 5. MeshCentral (Docker)

**What it is:** MeshCentral is an open-source, self-hosted Remote Monitoring and Management (RMM) platform — equivalent to ConnectWise Automate, TeamViewer, or NinjaRMM, but free and entirely on-prem. Created by Intel/Ylian Saint-Hilaire.

**What it does in this lab:**
- **Remote Desktop** — full graphical remote control of Windows or Linux VMs from your browser, with no VPN required (as long as agent port 4433 is reachable)
- **Terminal** — browser-based SSH/PowerShell terminal to any managed device
- **File Manager** — drag-and-drop file transfer to/from managed devices
- **Session Recording** — automatically records every remote session as a video file stored server-side. Critical for compliance and for your portfolio demo evidence
- **Agent persistence** — the MeshAgent service on each VM connects out to MeshCentral on port 4433 and maintains a persistent WebSocket connection. You can remote in even if the VM has no public IP, because the agent initiates the connection

**How the architecture works:**
```
Your Browser
    ↕ HTTPS :8086
MeshCentral Container ←→ Agent Port :4433
    ↕                          ↕
Docker Volume              VM (DC01/WS01)
(recordings, data)         MeshAgent service
                           (connects OUT to :4433)
```

The key insight: **the agent connects out, not in**. This means you don't need to open firewall ports to each VM — you only need port 4433 reachable on the Docker host (192.168.10.50) from the Host-Only network. Every VM with an agent installed will then appear in your MeshCentral dashboard.

**Device Groups (Meshes):**
Each Device Group has a unique cryptographic ID. This ID is embedded in the agent installer binary. When an agent runs, it uses the embedded ID to register itself with the correct group. This is how MeshCentral knows which group to put a device in.

**The `config.json`:**
Controls MeshCentral's behavior — hostname (must match the TLS cert CN), ports, whether new account creation is allowed, session recording settings, and user group definitions. The lab config pre-creates IT-Helpdesk and Network-Ops user groups.

---

### 6. Nginx Reverse Proxy (Docker)

**What it is:** Nginx (pronounced "engine-x") is a high-performance web server and reverse proxy. In this lab it's a lightweight container that sits in front of osTicket.

**What it does:**
- Listens on port 8080 (the port you access from your browser)
- Forwards all requests to the `osticket_app` container on its internal Docker network port 80
- Adds security headers (`X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection`)
- Handles large file uploads (sets `client_max_body_size 20M` for ticket attachments)

**Why not just expose osTicket directly on port 8080?**
Best practice is to never expose application servers directly. The reverse proxy:
- Handles TLS termination (in production, HTTPS certificates live here, not in the app)
- Can rate-limit requests to prevent brute force on the login page
- Provides a single point to add security headers to all responses
- Lets you run multiple web apps on one Docker host on one port (different `server_name` blocks)

---

### 7. Splunk Enterprise — SIEM

**What it is:** Splunk is a Security Information and Event Management (SIEM) platform. It collects log data from across your infrastructure, indexes it for fast search, and lets you build alerts and dashboards on top of it.

**What it does in this lab:**
- Receives Windows Event Logs from DC01 and WS01 via the **Splunk Universal Forwarder** — a lightweight agent that tails event log channels and ships them to Splunk over TCP 9997
- Indexes logs by `sourcetype` — `WinEventLog:Security`, `WinEventLog:System`, etc. The `sourcetype` tells Splunk's parsers what format the data is in
- **SPL (Splunk Processing Language)** — the query language. Like SQL but designed for time-series log data. The `|` pipe character chains transformations
- **Saved Searches/Alerts** — SPL queries that run on a schedule. When the result count exceeds a threshold, Splunk fires the alert (email, webhook, etc.)
- **Dashboards** — collections of panels, each backed by an SPL query. The "Helpdesk Operations" dashboard gives a single-pane-of-glass view of AD security events

**Key Windows Event IDs this lab monitors:**

| Event ID | What it means | Why it matters |
|----------|--------------|----------------|
| 4625 | Failed logon attempt | 5+ in 10 min = brute force |
| 4740 | Account locked out | User can't work; needs immediate unlock |
| 4720 | New user account created | Unauthorized accounts = insider threat |
| 4724 | Password reset (admin) | Audit trail for helpdesk actions |
| 4728/4732/4756 | User added to group | Privilege escalation detection |
| 5136 | AD object modified | GPO tampering detection |
| 4719 | Audit policy changed | Attacker disabling logging |
| 4767 | Account unlocked | Helpdesk action audit trail |

**The Universal Forwarder:**
A ~50 MB agent installed on each Windows machine. It reads from Windows Event Log channels and sends the data to your Splunk indexer. It's configured via `inputs.conf` — you specify which event log channels to monitor (Security, System, Application) and which Splunk server to send to (`outputs.conf`). The forwarder uses port 9997 (Splunk-to-Splunk protocol, not HTTPS).

---

### 8. PowerShell Helpdesk Scripts

**What they are:** Five production-grade PowerShell scripts for the most common L1/L2 helpdesk tasks, plus a shared library and interactive menu launcher.

**The shared library (`00-helpdesk-common.ps1`):**
Dot-sourced by every other script (`. "$PSScriptRoot\00-helpdesk-common.ps1"`). Contains:
- `Write-HDLog` — writes timestamped, level-coded entries to `C:\IT\Logs\Helpdesk\helpdesk-YYYY-MM.log`
- `Get-ValidatedADUser` — wraps `Get-ADUser` with proper error handling for the "user not found" case
- `Show-UserSummary` — prints a formatted user summary (name, dept, title, status, last logon)
- `New-TempPassword` — generates a random 14-character password meeting CorpTech's policy (excludes ambiguous characters like `O/0`, `l/1/I`)
- `Write-Banner` / `Write-Result` — consistent formatting across all scripts

**`01-reset-password.ps1` — Password Reset**
Uses `Set-ADAccountPassword -Reset` (admin override, bypasses old password check) then `Set-ADUser -ChangePasswordAtLogon $true`. Copies the temp password to clipboard. If the account was also locked, unlocks it in the same operation. `-WhatIf` support means you can simulate the reset without making changes.

**`02-unlock-account.ps1` — Account Unlock**
First checks `$user.LockedOut` — if not actually locked, it explains what else might prevent login (disabled account, expired password) instead of doing nothing silently. Then queries the PDC Emulator's Security event log for Event 4740 using `Get-WinEvent -FilterXml` to find the exact workstation that triggered the lockout. This root cause information is what separates a good helpdesk tech from a great one.

**`03-add-to-group.ps1` — Group Membership Management**
Uses `Get-ADGroup -Filter "Name -eq '$grpName'"` and falls back to a fuzzy `*$grpName*` search if not found — so you can type `SharedDrive` instead of the full `GRP-SharedDrive-RW`. Checks current membership before adding to prevent duplicate errors. Accepts multiple group names in one call. The `-Remove` switch flips it to removal mode, with an extra warning for groups matching admin naming patterns.

**`04-offboard-user.ps1` — Employee Offboarding**
The most complex script — 10 sequential steps with confirmation gate (must retype the username). Key details:
- Password is reset to a random value that's never stored (not even logged) — the account becomes permanently inaccessible without an admin manually setting a new password
- Removes from ALL groups except `Domain Users` (can't remove from primary group)
- Moves to `OU=Disabled` — keeping the account there for 90 days (per the audit report) gives HR time to retrieve mailbox data, project ownership, etc.
- Sets `msExchHideFromAddressLists = $true` — removes from Outlook's Global Address List so people can't accidentally email the departed person
- Generates a text audit report with a follow-up checklist (equipment retrieval, VPN revocation, non-AD systems) — this is what you'd hand to HR after offboarding

**`05-map-drive.ps1` — Network Drive Mapping**
Tests ICMP (ping) and then port 445 (SMB) before attempting to map — gives a useful error immediately instead of a cryptic "network path not found." Can run locally or be sent via `Invoke-Command` to a remote machine (uses WinRM). Uses `net use` as the primary mapping method because it works in all contexts including logon scripts and remote sessions where `New-PSDrive` can be scope-limited.

**`helpdesk-tools.ps1` — Interactive Menu Launcher**
A terminal UI (TUI) built entirely in PowerShell. Uses a `while ($true)` loop with a `switch` statement to dispatch to each script. Also includes three utility functions not in individual scripts: user lookup (fuzzy search across SAMAccountName, DisplayName, EmailAddress), group listing with member counts, and a domain health check that tests DC reachability, DNS, SYSVOL share, NETLOGON share, and FSMO role query.

---

## Step-by-Step Deployment Guide

### Phase 0 — Prepare Your Host Machine

**Minimum host specs:**
- CPU: 4+ cores with Intel VT-x or AMD-V enabled in BIOS (required for 64-bit VMs)
- RAM: 16 GB minimum (DC01: 4 GB, WS01: 4 GB, Docker on host: remainder)
- Storage: 150 GB free disk space (DC01: 60 GB, WS01: 40 GB, Docker volumes: ~10 GB)
- OS: Windows 10/11, macOS, or Linux — VirtualBox runs on all three

**Software to install before starting:**
1. Oracle VirtualBox 7.x — from virtualbox.org
2. VirtualBox Extension Pack (same version as VirtualBox) — enables USB 2.0/3.0, RDP

**ISOs to download:**
1. Windows Server 2022 Evaluation ISO — from Microsoft Evaluation Center (free, 180-day eval)
2. Windows 11 ISO — from Microsoft Media Creation Tool
3. Splunk Enterprise installer — from splunk.com (free developer license or 60-day trial)

---

### Phase 1 — Configure VirtualBox Host-Only Networks

Before creating any VMs, set up the two virtual networks.

1. Open VirtualBox → **File > Host Network Manager** (or **Tools > Network** in newer versions)
2. Create **vboxnet0** (Corporate LAN):
   - IPv4 Address: `192.168.10.1`
   - IPv4 Mask: `255.255.255.0`
   - DHCP Server: **Disabled**
3. Create **vboxnet1** (Management):
   - IPv4 Address: `192.168.20.1`
   - IPv4 Mask: `255.255.255.0`
   - DHCP Server: **Disabled**

> Both networks use static IPs only. Disabling DHCP ensures your VMs always have predictable addresses.

---

### Phase 2 — Create and Configure DC01

**Create the VM:**
```
Name:     DC01
Type:     Microsoft Windows
Version:  Windows 2022 (64-bit)
RAM:      4096 MB
Disk:     60 GB, VDI, Dynamically Allocated
```

**VM Settings** (after creation, before first boot):
- **System > Processor:** 2 CPUs, enable PAE/NX
- **System > Acceleration:** Enable VT-x/AMD-V, Nested Paging
- **Display > Screen:** 128 MB video memory, VMSVGA
- **Storage:** Attach Windows Server 2022 ISO to the IDE optical drive
- **Network > Adapter 1:** Host-Only Adapter → `vboxnet0`

**Install Windows Server 2022:**
1. Boot VM from ISO
2. Select **"Windows Server 2022 Standard Evaluation (Desktop Experience)"**
3. Choose **Custom Install** → select the unallocated disk → proceed
4. Set local Administrator password when prompted

**Install VirtualBox Guest Additions:**
- VM menu bar → **Devices > Insert Guest Additions CD Image**
- Run `VBoxWindowsAdditions.exe` inside the VM
- Reboot after installation

**Set static IP (in PowerShell as Administrator on DC01):**
```powershell
$nic = (Get-NetAdapter | Where-Object Status -eq Up).Name

New-NetIPAddress -InterfaceAlias $nic `
    -IPAddress 192.168.10.10 `
    -PrefixLength 24 `
    -DefaultGateway 192.168.10.1

Set-DnsClientServerAddress -InterfaceAlias $nic `
    -ServerAddresses "127.0.0.1","8.8.8.8"

ping 192.168.10.1 -n 2
```

**Transfer scripts to DC01:**

Option A — Shared Folder (recommended):
1. VM Settings > Shared Folders > Add
2. Point to your `IT_Simulation/` folder on the host
3. Enable Auto-mount, make it permanent
4. Inside the VM it will appear as a network drive (e.g., `Z:\`)

Option B — Drag and Drop:
- VM menu → Devices > Drag and Drop > Bidirectional
- Drag files from your host directly into the VM window

**Run the AD setup scripts in order:**
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force

# Stage 0: Installs ADDS role, promotes to DC. Server REBOOTS when done.
.\00-promote-dc.ps1

# ===== REBOOT HAPPENS HERE =====
# Log back in as CORP\Administrator

# Stage 1: OUs, groups, 10 users (~5 min)
.\01-configure-ad.ps1

# Stage 2: 4 GPOs created and linked (~3 min)
.\02-gpo-policies.ps1

# Stage 3: Verify — all checks should show [PASS]
.\03-verify-ad.ps1
```

**Expected output of Stage 3 (all green):**
```
  [PASS] Domain: corp.local
  [PASS] OU exists: IT
  [PASS] OU exists: HR
  [PASS] OU exists: Finance
  [PASS] jsmith | IT Systems Administrator | IT | Enabled
  ... (10 users)
  [PASS] CORP-Password-Policy (Status: AllSettingsEnabled)
  [PASS] \\DC01\CompanyShare exists at: C:\CompanyShare
  [PASS] DNS resolving corp.local successfully
  ALL CHECKS PASSED
```

---

### Phase 3 — Create and Configure WS01

**Create the VM:**
```
Name:     WS01
Type:     Microsoft Windows
Version:  Windows 11 (64-bit)
RAM:      4096 MB
Disk:     40 GB, VDI, Dynamically Allocated
```

**VM Settings:**
- **System > Processor:** 2 CPUs
- **System > Acceleration:** Enable VT-x/AMD-V
- **Storage:** Attach Windows 11 ISO
- **Network > Adapter 1:** Host-Only Adapter → `vboxnet0`

> Windows 11 requires TPM 2.0. If the installer blocks you, use the registry bypass during setup: at the "This PC can't run Windows 11" screen, press Shift+F10 to open cmd, then run `regedit` and add `HKEY_LOCAL_MACHINE\SYSTEM\Setup\MoSetup` → `AllowUpgradesWithUnsupportedTPMOrCPU` (DWORD = 1).

**Install Windows 11**, then install Guest Additions the same way as DC01.

**Set static IP and join domain:**
```powershell
$nic = (Get-NetAdapter | Where-Object Status -eq Up).Name

New-NetIPAddress -InterfaceAlias $nic `
    -IPAddress 192.168.10.20 `
    -PrefixLength 24 `
    -DefaultGateway 192.168.10.1

Set-DnsClientServerAddress -InterfaceAlias $nic `
    -ServerAddresses "192.168.10.10"

# Verify you can resolve the domain
Resolve-DnsName corp.local

# Join the domain (prompts for CORP\Administrator credential)
Add-Computer -DomainName "corp.local" `
             -Credential (Get-Credential CORP\Administrator) `
             -Restart -Force
```

After reboot, log in as `CORP\jsmith` (password: `Welc0me!2024`, must change immediately).
Verify: Z: drive is mapped automatically, login banner appears, USB drive is blocked.

**Verify GPO application:**
```powershell
gpresult /h C:\gpo-report.html /f
Start-Process "C:\gpo-report.html"
```
Look for all 4 CORP-* GPOs in the Applied GPOs section.

---

### Phase 4 — Set Up the Docker Host

Docker can run directly on your host machine (if it's Linux or you have Docker Desktop on Windows/Mac) or inside a dedicated Ubuntu VM in VirtualBox.

**Option A — Docker Desktop on Windows host (simplest):**
- Install Docker Desktop from docker.com
- Ensure WSL2 backend is enabled
- No additional VM needed — Docker runs on your host machine at `192.168.10.1` (or your host's IP on vboxnet0)
- Update `docker/.env`: set `HOST_IP` to your host machine's IP on the `vboxnet0` network

**Option B — Ubuntu VM in VirtualBox:**
```
Name:     docker-host
Type:     Linux
Version:  Ubuntu (64-bit)
RAM:      4096 MB
Disk:     60 GB, VDI, Dynamically Allocated
Network > Adapter 1: Host-Only Adapter → vboxnet0
Static IP: 192.168.10.50
```

Install Docker on Ubuntu:
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
docker --version  # should show 24+
```

**Deploy the lab stack (either option):**
```bash
cd IT_Simulation/docker

# Edit .env — set HOST_IP and MESH_HOSTNAME to the Docker host's IP on vboxnet0
nano .env

# Start all services
bash start-lab.sh up
bash start-lab.sh status
```

Expected output:
```
NAME                STATUS
osticket_db         running (healthy)
osticket_app        running
corptech_nginx      running
meshcentral         running
```

---

### Phase 5 — osTicket Post-Install

```
1. Open: http://<docker-host-ip>:8080/setup
2. Fill out the installer form:
   Helpdesk Name:  CorpTech IT Helpdesk
   Admin Email:    admin@corp.local
   Admin Username: admin
   Admin Password: (your choice — write it down)
   DB Host:        osticket-db
   DB Name:        osticket
   DB User:        osticket
   DB Password:    (value from your .env OST_DB_PASSWORD)
   Table Prefix:   ost_
3. Click Install Now — wait for "Congratulations" screen
4. IMPORTANT — delete the setup directory:
```

```bash
docker exec osticket_app rm -rf /var/www/html/setup
```

```bash
# Seed departments, SLA plans, help topics, staff, and 15 tickets
cd docker/osticket/seed
bash run-seed.sh

# Verify
bash run-seed.sh --verify
# Should show a table of all 15 tickets
```

```
5. Log into agent panel: http://<docker-host-ip>:8080/scp
   Username: admin | Password: (what you set above)
6. Set real passwords for alopez, tnguyen, mchen, jsmith:
   Admin Panel → Staff → click each agent → Set Password
```

Full guide: [`docker/osticket/POST-INSTALL.md`](../docker/osticket/POST-INSTALL.md)

---

### Phase 6 — MeshCentral Post-Install

```
1. Open: https://<docker-host-ip>:8086
   (Accept the browser's self-signed cert warning)
2. Create admin account:
   Username: admin | Email: admin@corp.local | Password: (your choice)
3. Create Device Group "CorpTech-Servers":
   My Account → Add Device Group → name it, enable Remote Desktop/Terminal/Files
4. Create Device Group "CorpTech-Workstations":
   Same process, different name
5. Get the Mesh ID for each group:
   Click group → ... menu → Copy Mesh ID
   Save both IDs — you need them for the agent installs
```

**Install agent on DC01** (run in elevated PowerShell on DC01):
```powershell
.\scripts\meshcentral\install-agent-windows.ps1 `
    -MeshHost 192.168.10.50 `
    -MeshPort 8086 `
    -MeshId '$$$mesh//CorpTech-Servers/PASTE_YOUR_MESH_ID_HERE'
```

**Install agent on WS01** (same script, different Mesh ID):
```powershell
.\scripts\meshcentral\install-agent-windows.ps1 `
    -MeshHost 192.168.10.50 `
    -MeshPort 8086 `
    -MeshId '$$$mesh//CorpTech-Workstations/PASTE_YOUR_MESH_ID_HERE'
```

Within 60 seconds, both VMs should appear as "Online" in MeshCentral.

Full guide: [`docker/meshcentral/POST-INSTALL.md`](../docker/meshcentral/POST-INSTALL.md)

---

### Phase 7 — Splunk Setup

**Install Splunk Enterprise** on a dedicated machine or VM at `192.168.20.10`:

If using a second VirtualBox VM, create it with:
```
Name:     splunk
RAM:      8192 MB (Splunk is memory-hungry)
Disk:     60 GB
Network > Adapter 1: Host-Only Adapter → vboxnet1
Static IP: 192.168.20.10
```

Then install Splunk (Linux recommended):
```bash
wget -O splunk.tgz 'https://download.splunk.com/products/splunk/releases/9.x.x/linux/splunk-9.x.x-linux-amd64.tgz'
tar -xf splunk.tgz -C /opt
/opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt \
    --seed-passwd 'Splunk!Admin2024'
/opt/splunk/bin/splunk enable boot-start
```

**On DC01 — Install Universal Forwarder:**
```powershell
# Download from splunk.com → Products → Universal Forwarder
# Install, then configure:
$splunkHome = "C:\Program Files\SplunkUniversalForwarder"

@'
[WinEventLog://Security]
disabled = 0
index = wineventlog

[WinEventLog://System]
disabled = 0
index = wineventlog

[WinEventLog://Application]
disabled = 0
index = wineventlog
'@ | Out-File "$splunkHome\etc\system\local\inputs.conf" -Encoding UTF8

@'
[tcpout]
defaultGroup = splunk-indexer

[tcpout:splunk-indexer]
server = 192.168.20.10:9997
'@ | Out-File "$splunkHome\etc\system\local\outputs.conf" -Encoding UTF8

Restart-Service SplunkForwarder
```

**Enable required audit policies on DC01:**
```cmd
auditpol /set /subcategory:"Directory Service Changes" /success:enable /failure:enable
auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable
auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Account Lockout" /success:enable /failure:enable
```

**Verify data is flowing in Splunk:**
```spl
index=wineventlog sourcetype="WinEventLog:Security" host="DC01" | head 5
```
If you get results, the forwarder is working.

**Install the dashboard and alerts:**
```bash
SPLUNK_HOME="/opt/splunk"
APP_DIR="$SPLUNK_HOME/etc/apps/corptech_helpdesk"
mkdir -p "$APP_DIR"/{local/data/ui/views,metadata}

cat > "$APP_DIR/app.conf" << 'EOF'
[launcher]
author=CorpTech IT
description=Helpdesk Operations Dashboard
version=1.0.0

[ui]
is_visible=true
label=CorpTech Helpdesk
EOF

cp splunk/dashboards/helpdesk-operations.xml \
   "$APP_DIR/local/data/ui/views/helpdesk_operations.xml"

cp splunk/alerts/savedsearches.conf \
   "$APP_DIR/local/savedsearches.conf"

sed -i 's/helpdesk@corp.local/your-email@domain.com/g' \
    "$APP_DIR/local/savedsearches.conf"

$SPLUNK_HOME/bin/splunk restart
```

Full guide: [`splunk/SETUP.md`](../splunk/SETUP.md)

---

### Phase 8 — Run the Helpdesk Demo

```powershell
# On DC01 — open the interactive helpdesk toolkit
Set-ExecutionPolicy Bypass -Scope Process -Force
.\scripts\powershell\helpdesk-tools.ps1
```

**Trigger a test lockout** (to see the Splunk alert fire and practice the unlock workflow):
```powershell
# On WS01 — attempt logon 6 times with wrong password to lock out djohnson
$cred = New-Object System.Management.Automation.PSCredential(
    "CORP\djohnson",
    (ConvertTo-SecureString "wrongpassword" -AsPlainText -Force)
)
1..6 | ForEach-Object {
    try { Start-Process cmd -Credential $cred -NoNewWindow } catch {}
}
```

Within 5 minutes, Splunk should trigger the "Account Lockout" alert. Then:
1. Check `http://192.168.20.10:8000 → Activity → Triggered Alerts`
2. Open osTicket, create a ticket for this lockout
3. Run `helpdesk-tools.ps1 → Option 2 → djohnson` — see the lockout source identified
4. Unlock the account, close the ticket

Follow the full end-to-end scenario in [`docker/meshcentral/DEMO-WORKFLOW.md`](../docker/meshcentral/DEMO-WORKFLOW.md).

---

### Phase 9 — Capture Screenshots & Record Demo

Follow the screenshot guide in `README.md`. For the MeshCentral remote session demo, use the workflow in `docker/meshcentral/DEMO-WORKFLOW.md`.

**Recommended recording setup:**
- OBS Studio: scene with your browser (MeshCentral) on left, osTicket on right
- Narrate what you're doing as you go — pretend you're explaining it in an interview
- Keep clips to 2-3 minutes each (deploy, ticket intake, remote support, resolution)
- Upload to YouTube (unlisted) or include as `.mp4` in a `docs/demo/` folder

---

### Troubleshooting Quick Reference

| Symptom | Check | Fix |
|---------|-------|-----|
| WS01 can't join domain | DNS set to 192.168.10.10? | `Set-DnsClientServerAddress` to DC01 IP |
| WS01 can't ping DC01 | Both on vboxnet0? | VirtualBox VM settings → Network → Adapter 1 → Host-Only → vboxnet0 |
| osTicket shows blank page | Setup dir still exists? | `docker exec osticket_app rm -rf /var/www/html/setup` |
| Seed script fails "table not found" | Web installer done? | Complete `http://host:8080/setup` first |
| MeshCentral agent offline | Port 4433 reachable? | Ping 192.168.10.50 from DC01; check Docker host firewall |
| Splunk no data | Forwarder running? | `Get-Service SplunkForwarder` on DC01 |
| Splunk no data | Index correct? | Try `index=*` in search to find where logs landed |
| Splunk unreachable from DC01 | vboxnet1 routing? | DC01 needs a second adapter on vboxnet1, or route added |
| GPO not applying | OU correct? | Run `gpresult /r` on WS01 — check Applied GPOs |
| Z: drive not mapped | User in group? | `Get-ADGroupMember GRP-SharedDrive-RW` |
| 4740 events missing | Audit policy? | `auditpol /get /subcategory:"Account Lockout"` |
| 5136 events missing | DS Changes audit? | `auditpol /set /subcategory:"Directory Service Changes" /success:enable` |
| Win11 install blocks TPM | TPM bypass needed | Registry bypass via Shift+F10 at setup screen |
