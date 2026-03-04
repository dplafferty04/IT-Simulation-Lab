# MeshCentral Post-Deploy Setup Guide

## Overview

MeshCentral provides self-hosted remote desktop, file transfer, and terminal
access — similar to TeamViewer or ConnectWise, but fully on-prem. In this lab
it's the tool you'd use to "remote in" to a user's machine during a helpdesk
ticket resolution.

---

## Step 1 — Start the Container

```bash
cd IT_Simulation/docker
bash start-lab.sh up
```

MeshCentral takes ~60 seconds to generate its self-signed certificate on first
boot. Watch it with:
```bash
docker logs meshcentral -f
```

Wait until you see:
```
MeshCentral HTTP server running on port 80.
MeshCentral HTTPS server running on port 443.
```

---

## Step 2 — Create the Admin Account

Open `https://<docker-host-ip>:8086` in a browser.

> Your browser will warn about the self-signed certificate — click through
> (Advanced → Proceed). In a real deployment you'd use a valid cert.

On first launch you will see the account creation screen:

| Field            | Value                        |
|------------------|------------------------------|
| Username         | `admin`                      |
| Password         | *(strong password of choice)*|
| Email            | `admin@corp.local`           |

Click **"Create Account"** — this becomes the sole admin account because
`ALLOW_NEW_ACCOUNTS=false` is set in the config.

---

## Step 3 — Create Device Groups (Meshes)

Device Groups in MeshCentral are collections of managed machines. Create two:

### Group 1 — Workstations
`My Account → Add Device Group`

| Setting                  | Value                          |
|--------------------------|--------------------------------|
| Group Name               | `CorpTech-Workstations`        |
| Description              | Corporate Windows workstations |
| Features                 | ✅ Remote Desktop, ✅ Files, ✅ Terminal |
| Agent invitation required| No                             |
| Consent prompt           | No (internal lab)              |
| Session recording        | ✅ Yes (set index: true)       |

### Group 2 — Servers
`My Account → Add Device Group`

| Setting                  | Value                          |
|--------------------------|--------------------------------|
| Group Name               | `CorpTech-Servers`             |
| Description              | Proxmox VMs — servers          |
| Features                 | ✅ Remote Desktop, ✅ Files, ✅ Terminal |
| Session recording        | ✅ Yes                         |

---

## Step 4 — Get the Mesh ID for Each Group

The Mesh ID is embedded in the agent installer — each group gets a unique ID.

1. In MeshCentral, click your device group name
2. Click the **"..."** (kebab menu) on the group
3. Select **"Copy Mesh ID"**

The ID looks like:
```
$$$mesh//CorpTech-Workstations/AAAABBBBCCCCDDDDEEEE...
```

**Save both IDs** — you'll need them for the agent install scripts.

---

## Step 5 — Install Agents on VMs

### On DC01 (Windows Server — Domain Controller)

Copy `scripts/meshcentral/install-agent-windows.ps1` to DC01, then run in
an elevated PowerShell session:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force

.\install-agent-windows.ps1 `
    -MeshHost  192.168.10.50 `
    -MeshPort  8086 `
    -MeshId    '$$$mesh//CorpTech-Servers/YOUR_MESH_ID_HERE' `
    -GroupName 'CorpTech-Servers'
```

### On WS01 (Windows 10/11 Workstation — domain-joined)

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force

.\install-agent-windows.ps1 `
    -MeshHost  192.168.10.50 `
    -MeshPort  8086 `
    -MeshId    '$$$mesh//CorpTech-Workstations/YOUR_MESH_ID_HERE' `
    -GroupName 'CorpTech-Workstations'
```

### On a Linux VM (optional third node)

```bash
sudo bash install-agent-linux.sh \
    --host   192.168.10.50 \
    --port   8086 \
    --meshid '$$$mesh//CorpTech-Servers/YOUR_MESH_ID_HERE' \
    --group  'CorpTech-Servers'
```

> **Port 4433 must be reachable from VMs to the Docker host.**
> On pfSense, ensure VLAN 10 allows outbound TCP/4433 to the Docker host.
> This is the WebSocket port agents use to maintain their persistent connection.

---

## Step 6 — Configure User Accounts for Agents

Create agent-level accounts so helpdesk staff can log into MeshCentral
without admin rights.

`Admin → Users → Add User`

| Username   | Full Name         | Access Level     | Group Access          |
|------------|-------------------|------------------|-----------------------|
| `alopez`   | Ana Lopez         | User             | CorpTech-Workstations |
| `tnguyen`  | Tommy Nguyen      | User             | CorpTech-Workstations |
| `mchen`    | Michael Chen      | Operator         | Both groups           |
| `jsmith`   | James Smith       | Site Admin       | Both groups           |

**Access level meanings in this lab:**
- **User** — Remote control, file transfer, no admin settings
- **Operator** — Can create/delete device groups
- **Site Admin** — Full access (same as admin for the domain)

To set per-group permissions:
`Admin → Device Groups → [group name] → Edit → Permissions`
Add each user and set their permission level per group.

---

## Step 7 — Verify Devices Are Online

After running the agent installers, return to `https://<host>:8086`.

Under `My Devices` you should see:

```
CorpTech-Servers
  ■ DC01        [Online]   Windows Server 2022   192.168.10.10
  ■ LINUX-SRV01 [Online]   Ubuntu 22.04          192.168.10.15  (if deployed)

CorpTech-Workstations
  ■ WS01        [Online]   Windows 11            192.168.10.20
```

Green dot = agent connected. If a device shows offline:
```bash
# Windows — check service
sc query "Mesh Agent"
# Linux — check service
systemctl status meshagent
journalctl -u meshagent -n 50
```

---

## Step 8 — Enable Session Recording (for Demo Evidence)

MeshCentral can record all remote sessions — useful for demo evidence and
for your resume screenshots.

`Admin → Device Groups → CorpTech-Workstations → Edit`
- Session Recording: **Enabled**
- Record all sessions: **Yes**

Recordings are stored at:
```
Docker volume: meshcentral_user_files
Path inside container: /opt/meshcentral/meshcentral-files/recordings/
```

To copy recordings to your host:
```bash
docker cp meshcentral:/opt/meshcentral/meshcentral-files/recordings/ \
    IT_Simulation/docs/screenshots/session-recordings/
```

---

## Firewall / Network Requirements

| From         | To              | Port  | Protocol | Purpose                     |
|--------------|-----------------|-------|----------|-----------------------------|
| Browser      | Docker host     | 8086  | TCP/HTTPS| Web UI + agent WebSocket    |
| VM agents    | Docker host     | 4433  | TCP      | Agent persistent connection |
| Docker host  | (none required) | —     | —        | MeshCentral is server-side  |

On pfSense, the relevant VLAN 10 rule should be:
```
Action: Pass
Source: VLAN10_NET
Destination: 192.168.10.50 (Docker host)
Port: 4433
Protocol: TCP
Description: MeshCentral agent traffic
```

---

## Quick Feature Reference

| Feature              | How to Access in UI                          |
|----------------------|----------------------------------------------|
| Remote Desktop       | Click device → Remote Desktop tab            |
| File Manager         | Click device → Files tab                     |
| Terminal/Shell       | Click device → Terminal tab                  |
| Event Log viewer     | Click device → Events tab                    |
| Run command          | Click device → Run tab → enter command       |
| Wake-on-LAN          | Device list → right-click → Wake Device      |
| Script execution     | My Scripts → Add Script → run on device      |
| Session recordings   | My Files → Recordings                        |
