# osTicket Post-Install Guide

## Step 1 — Start the Stack

```bash
cd IT_Simulation/docker
bash start-lab.sh up
```

Wait ~60 seconds for MariaDB to initialize, then confirm containers are healthy:
```bash
bash start-lab.sh status
```

You should see `osticket_db`, `osticket_app`, `corptech_nginx`, and `meshcentral` all running.

---

## Step 2 — Run the Web Installer

1. Open `http://<your-docker-host-ip>:8080/setup` in a browser
2. Click **"Let's Go!"**
3. Fill in the installer form:

| Field               | Value                              |
|---------------------|------------------------------------|
| Helpdesk Name       | CorpTech IT Helpdesk               |
| Default Email       | helpdesk@corp.local                |
| Admin First Name    | IT                                 |
| Admin Last Name     | Admin                              |
| Admin Email         | admin@corp.local                   |
| Admin Username      | admin                              |
| Admin Password      | (choose a strong password)         |
| DB Host             | osticket-db                        |
| DB Name             | osticket                           |
| DB Username         | osticket                           |
| DB Password         | *(value from your .env file)*      |
| Table Prefix        | ost_                               |

4. Click **"Install Now"**
5. When installation completes, **delete the setup directory**:

```bash
docker exec osticket_app rm -rf /var/www/html/setup
```

> **Important:** osTicket will refuse to function until `/setup` is removed.

---

## Step 3 — Run the Seed Script

```bash
cd IT_Simulation/docker/osticket/seed
bash run-seed.sh
```

This will create in order:
- 4 SLA plans, 2 departments, 8 help topics
- 4 staff/agent accounts (jsmith, alopez, tnguyen, mchen)
- 6 end users (mapped from corp.local AD accounts)
- 15 realistic tickets with full message threads

Verify with:
```bash
bash run-seed.sh --verify
```

---

## Step 4 — Admin Panel Configuration

Log into the **Staff Control Panel**: `http://<ip>:8080/scp`
Username: `admin` | Password: *(what you set in Step 2)*

### 4a — Set Email Templates
`Admin Panel > Emails > Templates`
- Edit the "New Ticket" template to reference CorpTech branding

### 4b — Configure Ticket Queues
`Admin Panel > Queues`
Create these queue views for your agents:

| Queue Name         | Filter                            |
|--------------------|-----------------------------------|
| My Open Tickets    | Status=Open, Assigned=Me          |
| Unassigned         | Status=Open, Assigned=Nobody      |
| High Priority      | Status=Open, Priority=High/Crit   |
| Closing Today      | Status=Open, Due=Today            |

### 4c — Staff Passwords
The seed script sets placeholder hashed passwords. Set real passwords via:
`Admin Panel > Staff > (click agent) > Set Password`

Or have each agent use **"Forgot Password"** from the login page.

### 4d — System Settings
`Admin Panel > Settings > System`

| Setting                 | Value                  |
|-------------------------|------------------------|
| Helpdesk Status         | Online                 |
| Default Page Size       | 25                     |
| Default Ticket Number   | 6-digit sequence       |
| Auto-assign to creator  | Yes                    |
| Max Open Tickets (user) | 0 (unlimited)          |

---

## Step 5 — Verify Ticket States

Log in as different agents and confirm you can see:

| Login as | Should see                              |
|----------|-----------------------------------------|
| `admin`  | All 15 tickets, all departments         |
| `jsmith` | All tickets (admin), manage staff       |
| `alopez` | IT Helpdesk tickets assigned to her     |
| `tnguyen`| IT Helpdesk tickets assigned to him     |
| `mchen`  | Network Operations tickets              |

---

## Ticket Summary (15 seeded tickets)

| # | Subject (truncated)                    | Dept       | Status   | Agent    |
|---|----------------------------------------|------------|----------|----------|
| 100001 | Unable to log in — password expired | IT Help    | Closed   | alopez   |
| 100002 | Account locked — cannot access...   | IT Help    | Closed   | tnguyen  |
| 100003 | New hire onboarding — Marcus Reed   | IT Help    | Open     | jsmith   |
| 100004 | Finance floor printer offline       | IT Help    | Closed   | tnguyen  |
| 100005 | Monitor flickering randomly         | IT Help    | Open     | alopez   |
| 100006 | Laptop not booting — black screen   | IT Help    | Resolved | jsmith   |
| 100007 | Teams — no audio during calls       | IT Help    | Closed   | alopez   |
| 100008 | Excel crashes on large .xlsx files  | IT Help    | Open     | tnguyen  |
| 100009 | Outlook not receiving new emails    | IT Help    | Closed   | alopez   |
| 100010 | Cannot access Z: drive              | Net Ops    | Open     | mchen    |
| 100011 | WiFi dropping in Conference Room B  | Net Ops    | Closed   | mchen    |
| 100012 | Internet extremely slow — HR floor  | Net Ops    | Open     | mchen    |
| 100013 | VPN access request                  | IT Help    | Resolved | jsmith   |
| 100014 | Blue screen — DRIVER_IRQL error     | IT Help    | Open     | jsmith   |
| 100015 | Adobe Acrobat Pro install request   | IT Help    | Closed   | tnguyen  |

---

## Troubleshooting

**"Table ost_ticket_status does not exist"**
→ The web installer has not been completed. Do Step 2 first.

**Seed script fails with "Access denied"**
→ Check your `OST_DB_ROOT_PASSWORD` in the `.env` file matches what MariaDB was initialized with. If in doubt, run `bash start-lab.sh reset` and start over.

**Tickets created but no thread messages visible**
→ osTicket's `ost_thread_entry` body format matters. Ensure you are viewing the ticket in the agent panel (`/scp/tickets.php?id=...`), not the client portal.

**Container won't start**
→ Check logs: `docker logs osticket_app --tail 50`
