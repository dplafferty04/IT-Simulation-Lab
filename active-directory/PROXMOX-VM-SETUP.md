# Proxmox VM Setup — Windows Server 2022 Domain Controller

## VM Specifications (DC01)

| Setting          | Value                          |
|------------------|--------------------------------|
| VM Name          | DC01                           |
| OS               | Windows Server 2022 (Desktop)  |
| CPU              | 2 vCPUs (host type)            |
| RAM              | 4 GB                           |
| Disk             | 60 GB (thin provisioned)       |
| Network          | VirtIO NIC, VLAN 10 (Corp LAN) |
| Display          | VirtIO-GPU or SPICE            |

## Pre-flight Checklist

1. **Upload ISO** to Proxmox:
   - Go to Datacenter > Storage > ISO Images > Upload
   - Upload `Windows_Server_2022_*.iso`
   - Also upload the **VirtIO driver ISO** from:
     `https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso`

2. **Create the VM** in Proxmox web UI:
   ```
   General:    Name=DC01, VM ID=100
   OS:         ISO = Windows Server 2022 ISO, Type=Windows, Version=11
   System:     Machine=q35, BIOS=OVMF (UEFI), EFI disk=yes, TPM=no
   Disks:      32GB virtio-scsi-single, Cache=Write Back
   CPU:        2 cores, Type=host
   Memory:     4096 MB, Ballooning=OFF (Windows doesn't like ballooning)
   Network:    virtio, Bridge=vmbr0, VLAN Tag=10
   ```

3. **Attach VirtIO ISO** as a second CD-ROM (IDE2) so the Windows installer
   can see the VirtIO storage and network drivers.

## Windows Installation Steps

1. Boot from ISO, select "Windows Server 2022 Standard (Desktop Experience)"
2. Choose "Custom Install"
3. At the disk selection screen — **no disks visible?**
   - Click "Load Driver" > Browse > VirtIO ISO > `vioscsi\2k22\amd64`
   - Load the storage driver, then your disk will appear
4. Complete installation, set local Administrator password

## Network Configuration (BEFORE running scripts)

Open PowerShell on the new VM and set a **static IP**:

```powershell
# Replace with your actual VLAN 10 subnet details
$adapterName = (Get-NetAdapter | Where-Object Status -eq Up).Name

New-NetIPAddress -InterfaceAlias $adapterName `
    -IPAddress 192.168.10.10 `
    -PrefixLength 24 `
    -DefaultGateway 192.168.10.1

Set-DnsClientServerAddress -InterfaceAlias $adapterName `
    -ServerAddresses "127.0.0.1","8.8.8.8"

# Verify connectivity
ping 8.8.8.8 -n 2
```

> **Suggested IP scheme for this lab:**
> | Host        | IP             | Role                     |
> |-------------|----------------|--------------------------|
> | pfSense     | 192.168.10.1   | Default gateway / DNS    |
> | DC01        | 192.168.10.10  | AD DC, DNS server        |
> | Docker host | 192.168.10.50  | osTicket, MeshCentral    |
> | Test-WS01   | 192.168.10.20  | Windows 10/11 workstation|

## Running the Scripts

Copy the `active-directory/` folder to DC01 (drag-drop via SPICE clipboard,
USB, or SMB from your Docker host), then in an elevated PowerShell session:

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

On a Windows 10/11 VM (Test-WS01, IP 192.168.10.20):

```powershell
# Point DNS at DC01 first
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
