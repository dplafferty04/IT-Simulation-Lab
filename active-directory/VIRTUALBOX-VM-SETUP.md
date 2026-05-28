# VirtualBox VM Setup — Windows Server 2022 Domain Controller

## VM Specifications (DC01)

| Setting          | Value                          |
|------------------|--------------------------------|
| VM Name          | DC01                           |
| OS               | Windows Server 2022 (Desktop)  |
| CPU              | 2 vCPUs                        |
| RAM              | 4 GB                           |
| Disk             | 60 GB (dynamically allocated)  |
| Network          | Host-Only Adapter (Corp LAN)   |
| Display          | VMSVGA                         |

## Pre-flight Checklist

1. **Download ISO:**
   - Windows Server 2022 Evaluation ISO from Microsoft Evaluation Center
   - No additional driver ISOs required — VirtualBox uses its own Guest Additions

2. **Create the VM** in VirtualBox:
   ```
   Name:         DC01
   Type:         Microsoft Windows
   Version:      Windows 2022 (64-bit)
   RAM:          4096 MB
   Disk:         60 GB, VDI, Dynamically Allocated
   ```

3. **VM Settings** (after creation, before first boot):
   - **System > Processor:** 2 CPUs, enable PAE/NX
   - **System > Acceleration:** Enable VT-x/AMD-V, Nested Paging
   - **Display > Screen:** 128 MB video memory, VMSVGA
   - **Storage:** Attach Windows Server 2022 ISO to the IDE optical drive
   - **Network > Adapter 1:** Host-Only Adapter (`vboxnet0`)

## Network — Host-Only Adapter Setup

Before creating the VM, configure the host-only network in VirtualBox:

1. Go to **File > Host Network Manager**
2. Create or select `vboxnet0`
3. Set adapter IP: `192.168.10.1` / Mask: `255.255.255.0`
4. Disable DHCP server (we'll use static IPs)

> **Suggested IP scheme for this lab:**
> | Host        | IP             | Role                     |
> |-------------|----------------|--------------------------|
> | VirtualBox host | 192.168.10.1 | Default gateway        |
> | DC01        | 192.168.10.10  | AD DC, DNS server        |
> | Docker host | 192.168.10.50  | osTicket, MeshCentral    |
> | WS01        | 192.168.10.20  | Windows 10/11 workstation|

## Windows Installation Steps

1. Boot VM from ISO
2. Select **"Windows Server 2022 Standard Evaluation (Desktop Experience)"**
3. Choose **Custom Install**
4. Select the unallocated disk and proceed
5. Complete installation and set the local Administrator password

## Network Configuration (BEFORE running scripts)

Open PowerShell on the new VM and set a **static IP**:

```powershell
$adapterName = (Get-NetAdapter | Where-Object Status -eq Up).Name

New-NetIPAddress -InterfaceAlias $adapterName `
    -IPAddress 192.168.10.10 `
    -PrefixLength 24 `
    -DefaultGateway 192.168.10.1

Set-DnsClientServerAddress -InterfaceAlias $adapterName `
    -ServerAddresses "127.0.0.1","8.8.8.8"

# Verify connectivity to host machine
ping 192.168.10.1 -n 2
```

## Install VirtualBox Guest Additions (Recommended)

From the VirtualBox menu bar inside the running VM:
- **Devices > Insert Guest Additions CD Image**
- Run `VBoxWindowsAdditions.exe` inside the VM
- Reboot after installation

This enables shared clipboard, drag-and-drop, and better display scaling.

## Transfer Scripts to DC01

Options for copying the `active-directory/` folder to DC01:

**Option A — Shared Folder (recommended):**
1. VM Settings > Shared Folders > Add
2. Point to your `IT_Simulation/` folder on the host
3. Enable Auto-mount, make it permanent
4. Inside the VM it will appear as a network drive (e.g., `Z:\`)

**Option B — Drag and Drop:**
- With Guest Additions installed: VM menu > Devices > Drag and Drop > Bidirectional
- Drag files from host directly into the VM window

## Running the Scripts

In an elevated PowerShell session on DC01:

```powershell
# Set execution policy for this session only
Set-ExecutionPolicy Bypass -Scope Process -Force

# Stage 0: Install ADDS + promote (server WILL reboot)
.\00-promote-dc.ps1

# --- After reboot, log in as CORP\Administrator ---

# Stage 1: OUs, groups, and 10 user accounts
.\01-configure-ad.ps1

# Stage 2: GPOs
.\02-gpo-policies.ps1

# Stage 3: Verify everything
.\03-verify-ad.ps1
```

## Join a Workstation to the Domain

Create a second VM (WS01) using the same Host-Only network adapter, then:

```powershell
# On WS01 — set DNS to DC01 first
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "192.168.10.10"

# Join domain
Add-Computer -DomainName "corp.local" `
             -Credential (Get-Credential CORP\Administrator) `
             -Restart -Force
```

After reboot, log in as `CORP\jsmith` (or any user) — the Z: drive should
map automatically and the login banner should appear.

## Verify GPO Application on Client

```powershell
# Run on the workstation after joining domain
gpresult /h C:\gpo-report.html /f
Start-Process "C:\gpo-report.html"
```

Look for all 4 CORP-* GPOs in the Applied GPOs section.
