# MeshCentral Demo Workflow
## "Helpdesk Remote Support Session" — Scenario Script

This document walks through a realistic remote support scenario you can
perform live during an interview or record as a demo video. It ties together
osTicket (ticket intake) → MeshCentral (remote access) → PowerShell scripts
(resolution) in one end-to-end flow.

---

## Scenario: Ticket #100008 — Excel Crashes on Large File

**Situation:** Karen Thompson (Finance) filed a ticket because Excel crashes
every time she opens `Q4_2024_Forecast.xlsx`. You are Ana Lopez (L1 Helpdesk)
responding to the ticket.

**Goal:** Demonstrate remote desktop, event log review, file transfer, and
resolution — all documented in the ticket.

---

## Phase 1 — Accept the Ticket in osTicket (2 min)

1. Log into `http://<host>:8080/scp` as `alopez`
2. Click **Ticket #100008** — "Excel crashes when opening large .xlsx files"
3. Read the thread — note kthompson already tried Safe Mode and local copy
4. Click **"Claim"** to assign to yourself
5. Change **Status** from `Open` to `In Progress`
6. Post an **Internal Note** (not visible to user):
   ```
   Remoting in via MeshCentral to WS Finance-WS-02.
   Will check: Office event logs, recent Windows Updates, add-in conflicts.
   ```

---

## Phase 2 — Connect via MeshCentral (1 min)

1. Open `https://<host>:8086` — log in as `alopez`
2. Navigate to **CorpTech-Workstations**
3. Click **WS01** (or Finance-WS-02 if that's your test VM name)
4. Click the **Remote Desktop** tab
5. Connection opens — you are now controlling the remote workstation

> **For the demo recording:** Narrate what you're doing:
> *"I'm connecting to Karen's workstation remotely through our self-hosted
> MeshCentral instance — no third-party RMM tool required."*

---

## Phase 3 — Diagnose the Issue (3 min)

### 3a — Check Windows Event Logs

In the MeshCentral terminal tab, run:
```powershell
# Pull Application log errors from the last 24 hours
Get-EventLog -LogName Application -EntryType Error -Newest 20 |
    Where-Object { $_.Source -match "Microsoft Office|Excel|WINWORD" } |
    Select-Object TimeGenerated, Source, EventID, Message |
    Format-List
```

Look for **Event ID 1000** (Application crash) — note the faulting module.

### 3b — Check for Recent Windows Updates

```powershell
# Show updates installed in last 7 days
Get-HotFix | Where-Object { $_.InstalledOn -gt (Get-Date).AddDays(-7) } |
    Select-Object HotFixID, Description, InstalledOn |
    Sort-Object InstalledOn -Descending
```

### 3c — Check Excel Add-ins (common crash cause)

```powershell
# List COM add-ins registered for Excel
Get-ItemProperty "HKCU:\Software\Microsoft\Office\16.0\Excel\Add-in Manager\*" `
    -ErrorAction SilentlyContinue | Select-Object PSChildName
```

### 3d — Collect Crash Dump for Evidence

```powershell
# Find crash minidumps
Get-ChildItem "C:\Users\*\AppData\Local\CrashDumps\*.dmp" -ErrorAction SilentlyContinue |
    Select-Object FullName, Length, LastWriteTime

# Also check WER (Windows Error Reporting) reports
Get-ChildItem "C:\ProgramData\Microsoft\Windows\WER\ReportArchive\*" |
    Where-Object { $_.Name -match "EXCEL" } |
    Select-Object Name, LastWriteTime | Sort-Object LastWriteTime -Descending
```

---

## Phase 4 — Resolve the Issue (2 min)

### Common Fix: Repair Office Installation

In the MeshCentral terminal (run as admin):

```powershell
# Option A: Quick repair (no download needed, ~2 min)
Start-Process "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe" `
    -ArgumentList "scenario=Repair DisplayLevel=False RepairType=QuickRepair" `
    -Wait

# Option B: If Quick Repair fails — Online Repair (downloads fresh files, ~10 min)
# Start-Process "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe" `
#     -ArgumentList "scenario=Repair DisplayLevel=False RepairType=FullRepair" -Wait
```

### Alternative Fix: Disable All Add-ins

```powershell
# Disable all Excel COM add-ins via registry
$addInKey = "HKCU:\Software\Microsoft\Office\16.0\Excel\Add-in Manager"
if (Test-Path $addInKey) {
    Get-ChildItem $addInKey | ForEach-Object {
        Set-ItemProperty -Path $_.PSPath -Name "Load Behavior" -Value 0 -ErrorAction SilentlyContinue
    }
    Write-Host "All Excel add-ins disabled."
}
```

### Test the Fix

Using the MeshCentral **Files** tab:
1. Navigate to `Z:\Finance\Models\` (the shared drive)
2. Right-click `Q4_2024_Forecast.xlsx` → **Open on Remote Machine**
3. Confirm Excel opens without crashing

---

## Phase 5 — Transfer a Support Tool via Files Tab (1 min)

> **Demonstrate file transfer capability:**

1. In MeshCentral, click the **Files** tab
2. Navigate to `C:\Temp\` on the remote machine
3. Click **Upload** and drag `scripts/powershell/helpdesk-tools.ps1`
   from your local machine to the remote machine
4. Narrate: *"I can push scripts, patches, or files directly through
   MeshCentral without needing a separate file share."*

---

## Phase 6 — Close the Ticket in osTicket (2 min)

Return to `http://<host>:8080/scp` as `alopez` and update Ticket #100008:

**Reply to user (visible to Karen):**
```
Hi Karen,

I have resolved the Excel crash issue on Finance-WS-02.

Root cause: A corrupted Excel add-in (Adobe PDF Maker) was conflicting
with the version of Office installed on your workstation after last
week's Windows Update (KB5034441).

Actions taken:
  1. Connected remotely via IT remote support tools
  2. Reviewed Windows Event Log — confirmed faulting module: pdfmaker.dll
  3. Performed Office Quick Repair via Click-to-Run repair utility
  4. Disabled conflicting Adobe add-in (not needed for your workflow)
  5. Verified Q4_2024_Forecast.xlsx opens successfully (tested 3 times)

Your workstation is fully operational. The file opens in ~8 seconds
on the first load (normal for a 45MB file with macros).

Please let me know if the issue recurs.

— Ana Lopez | IT Helpdesk | Ext. 5902
```

**Ticket fields to update:**
- Status: `Resolved`
- Close Note: `Office Quick Repair + Adobe add-in disabled. Verified fix.`
- Time Spent: `45 minutes`

---

## What This Demo Shows an Interviewer

| Skill Demonstrated       | Evidence                                          |
|--------------------------|---------------------------------------------------|
| Ticketing system usage   | Ticket claimed, updated, internal notes, resolved |
| Remote support tools     | MeshCentral connection, terminal, file transfer   |
| Windows troubleshooting  | Event logs, Office repair, add-in management      |
| PowerShell proficiency   | Diagnostic commands run in terminal tab           |
| Documentation            | Professional ticket reply with root cause + steps |
| SLA awareness            | Ticket marked appropriately, time logged          |
| Security mindset         | Self-hosted RMM (no data leaving the network)     |

---

## Recording Tips

If capturing this as a demo video for GitHub/portfolio:

1. **Start recording** before connecting to MeshCentral — show the full flow
2. Use the **MeshCentral session recording** feature (stored server-side)
3. Keep a **split view**: osTicket on left, MeshCentral on right
4. Narrate key decisions: *"I'm using internal notes rather than a reply
   so the user doesn't see my diagnostic steps"*
5. Show the **before state** (ticket open) and **after state** (ticket resolved)
   with timestamps visible

For screenshots, capture:
- MeshCentral device list (shows both VMs online)
- Active remote desktop session
- osTicket ticket thread with your resolution reply
- MeshCentral session recordings list
