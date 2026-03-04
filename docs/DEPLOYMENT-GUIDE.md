# Enterprise IT Simulation Lab — Full Deployment Guide

## What Each Component Does & Why It Exists

---

### 1. Proxmox VE — The Hypervisor

**What it is:** Proxmox is an open-source Type-1 hypervisor (bare metal). It runs directly on your server hardware and hosts all your virtual machines. Think of it as the foundation every other component sits on.

**What it does in this lab:**
- Hosts DC01 (Windows Server 2022) and WS01 (Windows 11) as KVM virtual machines
- Provides SPICE/VNC console access to VMs without needing a separate monitor
- Lets you snapshot VMs before destructive tests (like offboarding scripts)
- Manages virtual networking — each VM gets a virtual NIC connected to a virtual bridge (`vmbr0`), which your pfSense VM tags with VLANs

**Why you need it:** Without a hypervisor you'd need multiple physical machines. Proxmox lets you run the entire lab on one box.

**Key concepts:**
- **VM** — a full virtual computer with its own CPU, RAM, and disk, completely isolated from other VMs
- **VirtIO** — paravirtualized drivers that give VMs near-native disk and network performance. Required for Windows VMs on Proxmox — without them the Windows installer won't see the disk
- **Thin provisioning** — the VM's disk file only uses the space that's actually written, not the full allocated size. A 60 GB disk might only use 15 GB on the Proxmox host

---

### 2. pfSense — The Firewall & VLAN Router

**What it is:** pfSense is an open-source firewall and router OS, typically running as a VM in a homelab. It controls all traffic between your VLANs and to/from the internet.

**What it does in this lab:**
- **VLAN segmentation** — splits your lab into two broadcast domains: VLAN 10 (Corporate LAN, where AD/Docker/workstations live) and VLAN 20 (Management, where Splunk lives). Devices on different VLANs can't talk to each other unless pfSense explicitly allows it
- **DHCP server** — hands out IP addresses to VMs (you override these with static leases for servers)
- **DNS forwarder** — forwards `corp.local` DNS queries to DC01, and everything else to your upstream DNS (8.8.8.8). This is what lets workstations resolve `\\DC01\CompanyShare` by name
- **Firewall rules** — enforces the principle of least privilege: Splunk can receive logs from VLAN 10, but VLAN 10 clients can't browse to Splunk's admin port unless a rule allows it

**Why you need it:** In a real corporate environment, servers and workstations are always on different network segments. Showing VLAN-aware firewall rules on your resume demonstrates you understand network security beyond just "plug everything into one switch."

**Key concepts:**
- **VLAN (Virtual LAN)** — a logical network segment. Devices on VLAN 10 send traffic tagged with `802.1Q` VLAN ID 10. The switch/pfSense strips or reads this tag and routes accordingly
- **Firewall rule order** — pfSense processes rules top-to-bottom, first match wins. A "deny all" at the bottom means anything not explicitly permitted is blocked
- **Static DHCP lease** — tells DHCP to always give the same IP to a specific MAC address. Cheaper than configuring a static IP inside the VM, and survives reimages

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

The key insight: **the agent connects out, not in**. This means you don't need to open firewall ports to each VM — you only need port 4433 open inbound on the Docker host. Every VM with an agent installed will then appear in your MeshCentral dashboard.

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

### Phase 0 — Prepare Your Hardware

**Minimum Proxmox host specs:**
- CPU: 6+ cores (2 for DC01, 2 for WS01, 2 for pfSense, remainder for Docker/Splunk)
- RAM: 24 GB minimum (DC01: 4GB, WS01: 4GB, pfSense: 1GB, Docker host: 4GB, Splunk: 8GB)
- Storage: 300 GB SSD (Proxmox OS: 50GB, VMs: 250GB)
- Network: 1x NIC minimum (Proxmox handles VLANs via 802.1Q on one NIC with a managed switch, or a second NIC for the WAN)

**ISOs to download before starting:**
1. Proxmox VE 8.x ISO — from proxmox.com
2. Windows Server 2022 Evaluation ISO — from Microsoft (free, 180-day eval)
3. Windows 11 ISO — from Microsoft Media Creation Tool
4. VirtIO driver ISO — from `https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso`
5. pfSense ISO — from pfsense.org (or OPNsense if you prefer)

---

### Phase 1 — Install Proxmox

1. Boot your server from the Proxmox ISO
2. Install to your primary disk, set the management IP (e.g. `192.168.1.100`)
3. After install, access the web UI: `https://192.168.1.100:8006`
4. Upload all ISOs to Proxmox: `Datacenter → Storage → local → ISO Images → Upload`

---

### Phase 2 — Set Up pfSense (VLAN Router/Firewall)

**Create the pfSense VM:**
```
General:  Name=pfSense, VM ID=100
OS:       pfSense ISO, Type=Other
System:   Default (SeaBIOS is fine for pfSense)
Disks:    8 GB, virtio-scsi
CPU:      1 core, type=host
Memory:   1024 MB
Network:  Adapter 1: WAN (bridge to your physical NIC)
          Adapter 2: LAN (bridge vmbr1, no VLAN tag — trunked)
```

**pfSense initial config:**
- WAN: DHCP from your home router (or static from your ISP block)
- LAN: `192.168.10.1/24` (VLAN 10 gateway)
- In pfSense web UI (`https://192.168.10.1`):

Add VLANs: `Interfaces → VLANs → Add`
- VLAN 10: tag 10, parent = your LAN NIC, description = "Corp LAN"
- VLAN 20: tag 20, parent = your LAN NIC, description = "Management"

Add DHCP for each VLAN: `Services → DHCP Server`
- VLAN 10: range `192.168.10.100-192.168.10.200`, DNS = `192.168.10.10` (DC01)
- VLAN 20: range `192.168.20.100-192.168.20.200`

Add static DHCP leases (after VMs are created and you have their MAC addresses):
```
192.168.10.10  → DC01
192.168.10.20  → WS01
192.168.10.50  → Docker host
192.168.20.10  → Splunk
```

**Firewall rules** — `Firewall → Rules → VLAN10`:
```
Action  Source          Destination          Port    Description
Pass    VLAN10_NET      192.168.10.10        443,389,88,445  AD services
Pass    VLAN10_NET      192.168.10.50        8080,8086,4433  Docker services
Pass    VLAN10_NET      192.168.20.10        9997    Splunk forwarder
Pass    VLAN10_NET      any                  80,443  Internet (general)
Block   VLAN10_NET      192.168.20.0/24      any     Block mgmt VLAN (except above)
```

---

### Phase 3 — Create and Configure DC01

**Create the VM in Proxmox:**
```
General:  Name=DC01, VM ID=101
OS:       Windows Server 2022 ISO, Type=Windows 11/2022
System:   Machine=q35, BIOS=OVMF (UEFI), EFI disk=32GB, TPM=disabled
Disks:    60GB, virtio-scsi-single, Write Back cache
CPU:      2 cores, type=host
Memory:   4096MB, Balloon=OFF
Network:  virtio, vmbr1, VLAN tag=10
```

Add the VirtIO ISO as a second CD-ROM drive before starting.

**Install Windows Server 2022:**
1. Start VM, open SPICE console, boot from ISO
2. Select: "Windows Server 2022 Standard (Desktop Experience)"
3. Custom Install → Load Driver → Browse → VirtIO ISO → `vioscsi\2k22\amd64` → Load
4. Select your disk, complete installation
5. Set local Administrator password: `TempLocal!P@ss2024`

**Set static IP before running scripts:**
```powershell
# In PowerShell as Administrator on DC01
$nic = (Get-NetAdapter | Where-Object Status -eq Up).Name
New-NetIPAddress -InterfaceAlias $nic -IPAddress 192.168.10.10 -PrefixLength 24 -DefaultGateway 192.168.10.1
Set-DnsClientServerAddress -InterfaceAlias $nic -ServerAddresses "127.0.0.1","8.8.8.8"
```

**Copy the project scripts to DC01:**
Option A — via SPICE console clipboard (small files): copy-paste content directly
Option B — via network share: on your admin workstation, share the `active-directory\` folder and access it from DC01 as `\\your-admin-pc-ip\share`
Option C — via USB ISO: create an ISO from the scripts folder and mount it in Proxmox

**Run the AD setup scripts in order:**
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force

# Stage 0: Installs ADDS role, promotes to DC. Server REBOOTS when done.
.\00-promote-dc.ps1

# ===== REBOOT HAPPENS HERE =====
# Log back in as CORP\Administrator (domain admin, password from script)

# Stage 1: OUs, groups, 10 users (run ~5 min)
.\01-configure-ad.ps1

# Stage 2: 4 GPOs created and linked (run ~3 min)
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

### Phase 4 — Create and Configure WS01

**Create VM:**
```
General:  Name=WS01, VM ID=102
OS:       Windows 11 ISO, Type=Windows 11/2022
System:   Machine=q35, BIOS=OVMF, EFI disk=32GB, TPM=v2.0 (required for Win11)
Disks:    40GB, virtio-scsi-single
CPU:      2 cores, type=host
Memory:   4096MB
Network:  virtio, vmbr1, VLAN tag=10
```

**Install Windows 11** (use VirtIO ISO for drivers, same as DC01 process)

**Set static IP and join domain:**
```powershell
# On WS01, as local Administrator
$nic = (Get-NetAdapter | Where-Object Status -eq Up).Name
New-NetIPAddress -InterfaceAlias $nic -IPAddress 192.168.10.20 -PrefixLength 24 -DefaultGateway 192.168.10.1
Set-DnsClientServerAddress -InterfaceAlias $nic -ServerAddresses "192.168.10.10"

# Verify you can resolve the domain
Resolve-DnsName corp.local

# Join the domain (prompts for CORP\Administrator credential)
Add-Computer -DomainName "corp.local" -Credential (Get-Credential CORP\Administrator) -Restart -Force
```

After reboot, log in as `CORP\jsmith` (password: `Welc0me!2024`, must change immediately).
Verify: Z: drive is mapped automatically, login banner appears, USB drive is blocked.

---

### Phase 5 — Set Up Docker Host

Your Docker host can be a Linux VM in Proxmox or your existing Docker machine.

**If creating a new Ubuntu VM:**
```
General:  Name=docker-host, VM ID=103
OS:       Ubuntu 22.04 LTS ISO
Disks:    100GB
CPU:      4 cores
Memory:   8192MB
Network:  virtio, vmbr1, VLAN tag=10
Static IP: 192.168.10.50
```

**Install Docker on Ubuntu:**
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
docker --version  # should show 24+
```

**Deploy the lab stack:**
```bash
# Clone or copy the project to the Docker host
git clone https://github.com/dplafferty04/enterprise-it-simulation-lab.git
cd enterprise-it-simulation-lab/docker

# Configure environment
cp .env.example .env      # or edit .env directly
nano .env
# Set: HOST_IP=192.168.10.50, MESH_HOSTNAME=192.168.10.50
# Change all passwords from the defaults

# Start everything
bash start-lab.sh up
bash start-lab.sh status  # all 4 containers should show healthy/running
```

---

### Phase 6 — osTicket Post-Install

```
1. Open: http://192.168.10.50:8080/setup
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
5. Log into agent panel: http://192.168.10.50:8080/scp
   Username: admin | Password: (what you set above)
6. Set real passwords for alopez, tnguyen, mchen, jsmith:
   Admin Panel → Staff → click each agent → Set Password
```

---

### Phase 7 — MeshCentral Post-Install

```
1. Open: https://192.168.10.50:8086
   (Accept the browser's self-signed cert warning)
2. Create admin account:
   Username: admin | Email: admin@corp.local | Password: (your choice)
3. Create Device Group "CorpTech-Servers":
   My Account → Add Device Group → name it, enable Remote Desktop/Terminal/Files
4. Create Device Group "CorpTech-Workstations":
   Same process, different name
5. Get the Mesh ID for each group:
   Click group → ... menu → Copy Mesh ID
   Save both IDs — you need them for Step 6
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

**Create agent accounts for helpdesk staff:**
```
Admin → Users → Add User
Create: alopez, tnguyen (User level, Workstations group)
Create: mchen (Operator level, both groups)
Create: jsmith (Admin level, both groups)
```

---

### Phase 8 — Splunk Setup

**Install Splunk Enterprise** on your Splunk VM (192.168.20.10):
```bash
# Download installer from splunk.com (requires free account)
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

# inputs.conf — which logs to collect
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

# outputs.conf — where to send
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

# Set your email address in the alerts
sed -i 's/helpdesk@corp.local/your-email@domain.com/g' \
    "$APP_DIR/local/savedsearches.conf"

$SPLUNK_HOME/bin/splunk restart
```

**Configure Splunk email** (for alerts):
`Settings → Server Settings → Email Settings`
- SMTP server: your mail relay or `localhost` if you have postfix/sendmail

---

### Phase 9 — Run the Helpdesk Demo

**Test the full workflow:**

```powershell
# On DC01 — open the interactive helpdesk toolkit
Set-ExecutionPolicy Bypass -Scope Process -Force
.\scripts\powershell\helpdesk-tools.ps1
```

**Trigger a test lockout** (to see Splunk alert fire and practice the unlock workflow):
```powershell
# On WS01 — run this to lock out djohnson (use test account, never production users carelessly)
# Attempt logon 6 times with wrong password:
$cred = New-Object System.Management.Automation.PSCredential(
    "CORP\djohnson",
    (ConvertTo-SecureString "wrongpassword" -AsPlainText -Force)
)
1..6 | ForEach-Object {
    try { Start-Process cmd -Credential $cred -NoNewWindow } catch {}
}
```

Within 5 minutes, Splunk should trigger the "Account Lockout" alert. Then:
1. Check `http://splunk:8000 → Activity → Triggered Alerts`
2. Open osTicket, create a ticket for this lockout
3. Run `helpdesk-tools.ps1 → Option 2 → djohnson` — see the lockout source identified
4. Unlock the account, close the ticket

---

### Phase 10 — Capture Screenshots & Record Demo

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
| osTicket shows blank page | Setup dir still exists? | `docker exec osticket_app rm -rf /var/www/html/setup` |
| Seed script fails "table not found" | Web installer done? | Complete `http://host:8080/setup` first |
| MeshCentral agent offline | Port 4433 open? | Check pfSense rule: VLAN10 → Docker host port 4433 |
| Splunk no data | Forwarder running? | `Get-Service SplunkForwarder` on DC01 |
| Splunk no data | Index correct? | Try `index=*` in search to find where logs landed |
| GPO not applying | OU correct? | Run `gpresult /r` on WS01 — check Applied GPOs |
| Z: drive not mapped | User in group? | `Get-ADGroupMember GRP-SharedDrive-RW` |
| 4740 events missing | Audit policy? | `auditpol /get /subcategory:"Account Lockout"` |
| 5136 events missing | DS Changes audit? | `auditpol /set /subcategory:"Directory Service Changes" /success:enable` |
