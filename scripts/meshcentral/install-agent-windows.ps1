#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Silent MeshCentral agent installer for Windows VMs (DC01, WS01, etc.)
    Downloads the agent directly from your self-hosted MeshCentral instance
    and installs it as a persistent Windows service.

.PARAMETER MeshHost
    IP or hostname of your MeshCentral Docker host (no protocol, no port).
    Example: 192.168.10.50

.PARAMETER MeshPort
    HTTPS port MeshCentral is listening on. Default: 8086

.PARAMETER MeshId
    The Mesh ID from MeshCentral (Admin > Mesh > Copy Mesh ID).
    Looks like: $$$mesh//YourMeshName/xxxxxxxxxxxxxxxxxxxx...

.PARAMETER GroupName
    Friendly name shown in MeshCentral UI for this device group.
    Default: CorpTech-Workstations

.PARAMETER SkipCertCheck
    Skip TLS certificate verification (use for self-signed certs in lab).
    Default: true (lab environment)

.EXAMPLE
    # On DC01 — run in elevated PowerShell
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\install-agent-windows.ps1 -MeshHost 192.168.10.50 -MeshId '$$$mesh//CorpTech-Workstations/abc123...'

.EXAMPLE
    # Non-interactive (for GPO/startup script deployment)
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-agent-windows.ps1 `
        -MeshHost 192.168.10.50 -MeshId '$$$mesh//CorpTech-Workstations/abc123...' -SkipCertCheck $true
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$MeshHost,

    [int]$MeshPort = 8086,

    [Parameter(Mandatory=$true)]
    [string]$MeshId,

    [string]$GroupName = "CorpTech-Workstations",

    [bool]$SkipCertCheck = $true
)

# ── Configuration ─────────────────────────────────────────────
$AgentDir     = "C:\Program Files\Mesh Agent"
$AgentExe     = "$AgentDir\MeshAgent.exe"
$ServiceName  = "Mesh Agent"
$TempDir      = $env:TEMP
$AgentInstaller = "$TempDir\MeshAgent-installer.exe"
$LogFile      = "$TempDir\meshagent-install.log"
$MeshServerUrl = "https://${MeshHost}:${MeshPort}"
# ──────────────────────────────────────────────────────────────

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp][$Level] $Msg"
    Add-Content -Path $LogFile -Value $line
    switch ($Level) {
        "INFO"  { Write-Host "  [*] $Msg" -ForegroundColor Cyan }
        "OK"    { Write-Host "  [+] $Msg" -ForegroundColor Green }
        "WARN"  { Write-Host "  [!] $Msg" -ForegroundColor Yellow }
        "ERROR" { Write-Host "  [ERR] $Msg" -ForegroundColor Red }
    }
}

Write-Host ""
Write-Host "══════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  MeshCentral Agent Installer — CorpTech Lab  " -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  Server : $MeshServerUrl"
Write-Host "  Group  : $GroupName"
Write-Host "  Log    : $LogFile"
Write-Host ""

Write-Log "Starting MeshCentral agent installation on $env:COMPUTERNAME"

# ── Step 1: Skip cert check if requested (lab self-signed cert) ──
if ($SkipCertCheck) {
    Write-Log "Disabling TLS certificate validation for self-signed cert"
    Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAll : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate cert,
        WebRequest req, int problem) { return true; }
}
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAll
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

# ── Step 2: Check if agent is already installed ───────────────
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Log "MeshAgent service already exists (status: $($existingService.Status))" "WARN"
    $choice = Read-Host "    Reinstall/update agent? (y/N)"
    if ($choice -notmatch '^[Yy]$') {
        Write-Log "Installation skipped by user." "WARN"
        exit 0
    }
    Write-Log "Stopping existing service for reinstall..."
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
}

# ── Step 3: Create agent directory ───────────────────────────
if (-not (Test-Path $AgentDir)) {
    New-Item -ItemType Directory -Path $AgentDir -Force | Out-Null
    Write-Log "Created agent directory: $AgentDir"
}

# ── Step 4: Download the Windows agent installer from MeshCentral ──
# MeshCentral generates a unique installer per mesh group containing
# the server URL, cert hash, and mesh ID embedded in the binary.
#
# Agent download URL format:
#   https://<host>:<port>/meshagents?script=1&id=<meshid>&installflags=0&meshinstall=6
#
# meshinstall values:
#   3  = Windows installer (MSI-style, 64-bit)
#   6  = Windows installer (EXE, 64-bit) ← use this
#   10 = Windows installer (32-bit)

$DownloadUrl = "${MeshServerUrl}/meshagents?script=1&meshinstall=6&id=${MeshId}&installflags=0"

Write-Log "Downloading agent from: $DownloadUrl"
try {
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($DownloadUrl, $AgentInstaller)
    $fileSize = (Get-Item $AgentInstaller).Length
    Write-Log "Downloaded agent installer ($([math]::Round($fileSize/1KB, 1)) KB)" "OK"
} catch {
    Write-Log "Download failed: $($_.Exception.Message)" "ERROR"
    Write-Log "Ensure MeshCentral is running and reachable at $MeshServerUrl" "ERROR"
    Write-Log "Also verify your MeshId is correct (copy from Admin > Mesh > right-click > Copy Mesh ID)" "ERROR"
    exit 1
}

# ── Step 5: Run installer silently ────────────────────────────
Write-Log "Installing MeshAgent (silent)..."
try {
    $installArgs = @("/Q", "/S", "/quiet")
    $proc = Start-Process -FilePath $AgentInstaller -ArgumentList $installArgs `
            -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Write-Log "Installer exited with code: $($proc.ExitCode)" "WARN"
    } else {
        Write-Log "Installer completed with exit code 0" "OK"
    }
} catch {
    # Some MeshCentral builds self-execute — try direct execution
    Write-Log "Standard install failed, trying self-extract method..." "WARN"
    Start-Process -FilePath $AgentInstaller -Wait -NoNewWindow
}

# ── Step 6: Verify service is running ────────────────────────
Start-Sleep -Seconds 5
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if ($svc -and $svc.Status -eq "Running") {
    Write-Log "MeshAgent service is RUNNING" "OK"
} elseif ($svc) {
    Write-Log "Service exists but status is: $($svc.Status) — attempting start..." "WARN"
    Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    $svc.Refresh()
    Write-Log "Service status after start attempt: $($svc.Status)" $(if($svc.Status -eq "Running"){"OK"}else{"WARN"})
} else {
    Write-Log "Service not found — installation may have failed. Check: $LogFile" "ERROR"
    Write-Log "Manual check: sc query 'Mesh Agent'" "ERROR"
    exit 1
}

# ── Step 7: Configure Windows Firewall ───────────────────────
Write-Log "Configuring Windows Firewall for MeshAgent..."
$fwRuleName = "MeshCentral Agent (Outbound)"
$existingRule = Get-NetFirewallRule -DisplayName $fwRuleName -ErrorAction SilentlyContinue
if (-not $existingRule) {
    New-NetFirewallRule -DisplayName $fwRuleName `
        -Direction Outbound `
        -Program $AgentExe `
        -Action Allow `
        -Protocol TCP `
        -RemotePort $MeshPort,4433 `
        -Profile Any | Out-Null
    Write-Log "Firewall rule created: $fwRuleName" "OK"
} else {
    Write-Log "Firewall rule already exists" "OK"
}

# ── Step 8: Clean up temp installer ──────────────────────────
Remove-Item $AgentInstaller -Force -ErrorAction SilentlyContinue
Write-Log "Cleaned up temp installer"

# ── Summary ───────────────────────────────────────────────────
Write-Host ""
Write-Host "══════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Log "Installation complete on $env:COMPUTERNAME" "OK"
Write-Host ""
Write-Host "  The device should appear in MeshCentral within 30-60 seconds."
Write-Host "  Browse to: $MeshServerUrl"
Write-Host "  Look for: $env:COMPUTERNAME under the '$GroupName' group"
Write-Host ""
Write-Host "  Service management:"
Write-Host "    Start : Start-Service 'Mesh Agent'"
Write-Host "    Stop  : Stop-Service 'Mesh Agent'"
Write-Host "    Status: Get-Service 'Mesh Agent'"
Write-Host ""
Write-Host "  Install log: $LogFile" -ForegroundColor DarkGray
Write-Host "══════════════════════════════════════════════" -ForegroundColor DarkCyan
