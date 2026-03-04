# Splunk Integration Setup Guide

## Prerequisites

Your existing Splunk instance must already be ingesting:
- **Windows Security Event Log** from DC01
- **Windows System Event Log** from DC01 (optional, for service events)

Verify data is flowing:
```spl
index=wineventlog sourcetype="WinEventLog:Security" host="DC01" | head 5
```

If this returns no results, check your Universal Forwarder config on DC01 (see below).

---

## Step 1 — Verify Universal Forwarder on DC01

On DC01, check that the Splunk Universal Forwarder is installed and sending
Security events. The relevant config file is:

`C:\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf`

It should contain at minimum:
```ini
[WinEventLog://Security]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5
renderXml = false
index = wineventlog

[WinEventLog://System]
disabled = 0
index = wineventlog

[WinEventLog://Application]
disabled = 0
index = wineventlog
```

Restart the forwarder after any change:
```powershell
Restart-Service SplunkForwarder
```

---

## Step 2 — Enable Required Audit Policies on DC01

Several queries rely on audit policies that are **not enabled by default**.
Run this on DC01 in an elevated PowerShell or Command Prompt:

```powershell
# Enable DS Access auditing (required for 5136 GPO change events)
auditpol /set /subcategory:"Directory Service Changes" /success:enable /failure:enable

# Enable Account Management auditing (4720, 4726, 4728, 4740, 4767)
auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable
auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable

# Enable Logon/Logoff auditing (4624, 4625, 4648)
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Account Lockout" /success:enable /failure:enable

# Verify current policy
auditpol /get /category:*
```

Or apply via GPO:
`Computer Config > Policies > Windows Settings > Security Settings >
Advanced Audit Policy Configuration > Audit Policies`

---

## Step 3 — Create the Splunk App

Create the app directory structure on your Splunk server:

```bash
# On your Splunk server (Linux) or Splunk home (Windows)
SPLUNK_HOME="/opt/splunk"   # adjust if needed
APP_DIR="$SPLUNK_HOME/etc/apps/corptech_helpdesk"

mkdir -p "$APP_DIR"/{local/data/ui/views,metadata,lookups,static}

# App manifest
cat > "$APP_DIR/app.conf" << 'EOF'
[launcher]
author=CorpTech IT
description=CorpTech Helpdesk Operations — AD security monitoring and alerting
version=1.0.0

[ui]
is_visible=true
label=CorpTech Helpdesk

[package]
id=corptech_helpdesk
EOF
```

---

## Step 4 — Install the Dashboard

```bash
# Copy dashboard XML
cp IT_Simulation/splunk/dashboards/helpdesk-operations.xml \
   "$APP_DIR/local/data/ui/views/helpdesk_operations.xml"

# Set metadata (makes dashboard visible to all users of the app)
cat > "$APP_DIR/metadata/local.meta" << 'EOF'
[]
access = read : [ * ], write : [ admin, power ]
export = system

[views/helpdesk_operations]
access = read : [ * ]
export = system
EOF
```

**OR via the Splunk UI:**
1. Go to `Settings > User Interface > Views`
2. Click `+ New View`
3. Name: `helpdesk_operations`
4. Paste the contents of `splunk/dashboards/helpdesk-operations.xml`
5. Save, then navigate to the view

---

## Step 5 — Install the Alerts

```bash
# Copy saved searches / alerts
cp IT_Simulation/splunk/alerts/savedsearches.conf \
   "$APP_DIR/local/savedsearches.conf"
```

Edit the file first to set your real email address:
```bash
sed -i 's/helpdesk@corp.local/your-real-email@domain.com/g' \
    "$APP_DIR/local/savedsearches.conf"
```

Then configure Splunk's email settings:
`Settings > Server Settings > Email Settings`
- Mail host: your SMTP relay or `localhost` (if you have an MTA)
- From: `splunk@corp.local`

Restart Splunk:
```bash
$SPLUNK_HOME/bin/splunk restart
```

---

## Step 6 — Verify the Dashboard

1. Navigate to `Apps > CorpTech Helpdesk > Helpdesk Operations`
2. You should see 6 rows of panels populate with data
3. If panels show "No results found", run each SPL query manually in the
   Search app to verify the index/sourcetype names match your environment

**Common index name variations — update `index=` in all query files if yours differs:**

| Your setup          | Replace `index=wineventlog` with |
|---------------------|----------------------------------|
| Default index       | `index=main`                     |
| Windows-specific    | `index=windows`                  |
| Custom index        | `index=<your-index-name>`        |

Quick check:
```spl
| metadata type=sourcetypes index=*
| search sourcetype="WinEventLog*"
```

---

## Step 7 — Verify Alerts

`Settings > Searches, Reports, and Alerts > filter: Alert`

You should see 5 alerts:
- ALERT - Account Lockout Detected
- ALERT - Brute Force Login Attempt
- ALERT - GPO or Audit Policy Changed
- ALERT - New AD User Account Created
- ALERT - After-Hours Admin Logon

**Test an alert manually:**

```powershell
# On a domain workstation — trigger a lockout for testing
# (use a test account, not a real user)
$cred = Get-Credential -UserName "CORP\testuser" -Message "Enter wrong password 6 times"
# Repeat logon attempts with wrong password until lockout fires
```

Then check Splunk: `Activity > Triggered Alerts`

---

## Alert Summary

| Alert Name                       | Trigger Condition                    | Schedule  | Severity |
|----------------------------------|--------------------------------------|-----------|----------|
| Account Lockout Detected         | Any Event 4740                       | Every 5m  | Medium   |
| Brute Force Login Attempt        | 5+ Event 4625 for same account/10min | Every 10m | High     |
| GPO or Audit Policy Changed      | Any 5136/5137/5141/4719 by non-SYSTEM| Every 5m  | High     |
| New AD User Account Created      | Any Event 4720                       | Every 5m  | Medium   |
| After-Hours Admin Logon          | Admin logon before 7am or after 7pm  | Hourly    | Medium   |

---

## Query File Reference

| File                               | What it finds                               |
|------------------------------------|---------------------------------------------|
| `queries/01-account-lockouts.spl`  | Lockout events + per-account frequency      |
| `queries/02-brute-force-logins.spl`| Failed logon clustering + spray detection   |
| `queries/03-gpo-changes.spl`       | GPO modifications, creations, deletions     |
| `queries/04-new-user-creation.spl` | Account lifecycle + privileged group adds   |
| `queries/05-helpdesk-summary.spl`  | All dashboard panel queries in one file     |

Each file contains multiple variants — read the comments. Uncomment the
`| comment {"..."}` blocks to run the alternate queries.
