-- ============================================================
-- osTicket Seed: 15 Realistic Helpdesk Tickets
-- Each ticket includes: subject, thread message, staff reply,
-- and resolution notes where applicable.
-- ============================================================

USE osticket;

-- ── Helper procedure ──────────────────────────────────────────
-- Creates a full ticket with initial message and optional reply.
-- status: 'open' | 'resolved' | 'closed'
-- priority: 1=low, 2=normal, 3=high, 4=critical

DROP PROCEDURE IF EXISTS seed_ticket;
DELIMITER //
CREATE PROCEDURE seed_ticket(
    IN p_number      VARCHAR(10),
    IN p_subject     VARCHAR(255),
    IN p_user_email  VARCHAR(128),
    IN p_dept_name   VARCHAR(128),
    IN p_topic_name  VARCHAR(128),
    IN p_sla_name    VARCHAR(128),
    IN p_priority    TINYINT,
    IN p_status      VARCHAR(20),   -- 'open','resolved','closed'
    IN p_source      VARCHAR(32),   -- 'web','email','phone'
    IN p_created     DATETIME,
    IN p_agent_user  VARCHAR(64),   -- staff username to assign
    IN p_body        TEXT,          -- user's initial message
    IN p_reply       TEXT           -- agent reply (NULL = no reply yet)
)
BEGIN
    DECLARE v_user_id     INT DEFAULT 0;
    DECLARE v_email_id    INT DEFAULT 0;
    DECLARE v_dept_id     INT DEFAULT 0;
    DECLARE v_topic_id    INT DEFAULT 0;
    DECLARE v_sla_id      INT DEFAULT 0;
    DECLARE v_staff_id    INT DEFAULT 0;
    DECLARE v_status_id   INT DEFAULT 1;
    DECLARE v_ticket_id   INT DEFAULT 0;
    DECLARE v_thread_id   INT DEFAULT 0;

    -- Skip if ticket number already exists
    IF EXISTS (SELECT 1 FROM ost_ticket WHERE number = p_number) THEN
        LEAVE sp_body;
    END IF;

    -- Lookups
    SELECT ue.user_id, ue.id INTO v_user_id, v_email_id
    FROM ost_user_email ue WHERE ue.address = p_user_email LIMIT 1;

    SELECT id INTO v_dept_id  FROM ost_department WHERE name = p_dept_name LIMIT 1;
    SELECT id INTO v_topic_id FROM ost_help_topic  WHERE topic = p_topic_name LIMIT 1;
    SELECT id INTO v_sla_id   FROM ost_sla         WHERE name = p_sla_name LIMIT 1;
    SELECT staff_id INTO v_staff_id FROM ost_staff  WHERE username = p_agent_user LIMIT 1;

    SELECT id INTO v_status_id FROM ost_ticket_status
    WHERE LOWER(name) = LOWER(p_status) LIMIT 1;

    IF v_status_id = 0 THEN SET v_status_id = 1; END IF;

    -- Insert ticket
    INSERT INTO ost_ticket
        (number, user_id, user_email_id, status_id, dept_id, sla_id, topic_id,
         staff_id, team_id, subject, source, ip_address, flags, isoverdue,
         created, updated, lastmessage, lastresponse,
         duedate, closed)
    VALUES (
        p_number,
        v_user_id,
        v_email_id,
        v_status_id,
        v_dept_id,
        v_sla_id,
        v_topic_id,
        v_staff_id,
        0,          -- team_id
        p_subject,
        p_source,
        '10.10.10.1',
        0,          -- flags
        0,          -- isoverdue
        p_created,
        p_created,
        p_created,
        IF(p_reply IS NOT NULL, DATE_ADD(p_created, INTERVAL 45 MINUTE), NULL),
        DATE_ADD(p_created, INTERVAL 8 HOUR),  -- duedate
        IF(p_status IN ('resolved','closed'), DATE_ADD(p_created, INTERVAL 2 HOUR), NULL)
    );

    SET v_ticket_id = LAST_INSERT_ID();

    -- Create thread
    INSERT INTO ost_thread (object_id, object_type, extra, created, updated)
    VALUES (v_ticket_id, 'T', '{}', p_created, p_created);

    SET v_thread_id = LAST_INSERT_ID();

    -- Initial user message
    INSERT INTO ost_thread_entry
        (thread_id, staff_id, user_id, type, flags, source, format,
         title, body, created, updated, poster)
    VALUES (
        v_thread_id,
        0,              -- staff_id = 0 (end user)
        v_user_id,
        'M',            -- M = message
        0,
        p_source,
        'html',
        p_subject,
        p_body,
        p_created,
        p_created,
        (SELECT name FROM ost_user WHERE id = v_user_id LIMIT 1)
    );

    -- Agent reply (if provided)
    IF p_reply IS NOT NULL AND v_staff_id > 0 THEN
        INSERT INTO ost_thread_entry
            (thread_id, staff_id, user_id, type, flags, source, format,
             title, body, created, updated, poster)
        VALUES (
            v_thread_id,
            v_staff_id,
            0,          -- user_id = 0 (agent)
            'R',        -- R = response
            0,
            'web',
            'html',
            CONCAT('Re: ', p_subject),
            p_reply,
            DATE_ADD(p_created, INTERVAL 45 MINUTE),
            DATE_ADD(p_created, INTERVAL 45 MINUTE),
            (SELECT CONCAT(firstname, ' ', lastname) FROM ost_staff WHERE staff_id = v_staff_id LIMIT 1)
        );
    END IF;

END //
DELIMITER ;

-- ══════════════════════════════════════════════════════════════
-- TICKETS
-- ══════════════════════════════════════════════════════════════

-- ── TICKET 1 — Password Reset (Closed) ───────────────────────
CALL seed_ticket(
    '100001',
    'Unable to log in — password expired',
    'djohnson@corp.local',
    'IT Helpdesk', 'Password Reset', 'High - 4 Hours',
    2, 'closed', 'web',
    DATE_SUB(NOW(), INTERVAL 28 DAY),
    'alopez',
    '<p>Hi IT Team,</p>
<p>I tried logging into my workstation this morning and received an error saying my password has expired. I cannot get past the login screen. I have an HR performance review meeting in 1 hour and need access urgently.</p>
<p>Workstation: HR-WS-04<br>Username: djohnson</p>
<p>Thanks,<br>David Johnson<br>HR Coordinator</p>',
    '<p>Hi David,</p>
<p>I have reset your password. Your temporary password is: <strong>Welc0me!Temp01</strong></p>
<p>Please log in and you will be prompted to set a new password. Your new password must be at least 14 characters and meet our complexity requirements.</p>
<p>If you have any trouble, call the helpdesk at ext. 5900.</p>
<p>Resolved — Ana Lopez, IT Helpdesk</p>'
);

-- ── TICKET 2 — Account Lockout (Closed) ──────────────────────
CALL seed_ticket(
    '100002',
    'Account locked — cannot access Outlook or workstation',
    'kthompson@corp.local',
    'IT Helpdesk', 'Account Lockout', 'High - 4 Hours',
    3, 'closed', 'phone',
    DATE_SUB(NOW(), INTERVAL 25 DAY),
    'tnguyen',
    '<p>Hello,</p>
<p>I am locked out of both my workstation and Outlook. I think I may have typed the wrong password too many times after coming back from vacation. I have a month-end financial close deadline today and need access ASAP.</p>
<p>Username: kthompson<br>Department: Finance</p>
<p>Karen Thompson</p>',
    '<p>Hi Karen,</p>
<p>I have unlocked your account in Active Directory. The lockout was triggered by 7 failed login attempts — likely saved credentials from before your vacation.</p>
<p><strong>Action taken:</strong> Account unlocked via AD Users & Computers. Cleared saved credentials on Finance-WS-02 remotely.</p>
<p>Please try logging in now. I would also recommend updating any saved passwords in your browser or applications. Let me know if you need further assistance.</p>
<p>— Tommy Nguyen, IT Helpdesk</p>'
);

-- ── TICKET 3 — New User Setup (Open, assigned) ───────────────
CALL seed_ticket(
    '100003',
    'New hire onboarding — Marcus Reed starting Monday',
    'swilliams@corp.local',
    'IT Helpdesk', 'New User Setup', 'Normal - 8 Hours',
    2, 'open', 'web',
    DATE_SUB(NOW(), INTERVAL 3 DAY),
    'jsmith',
    '<p>Hi IT,</p>
<p>We have a new Finance team member starting this Monday. Please create the necessary accounts and have a workstation ready.</p>
<p><strong>New Employee Details:</strong><br>
Name: Marcus Reed<br>
Title: Junior Accountant<br>
Department: Finance<br>
Manager: Raj Patel (rpatel)<br>
Start Date: Monday<br>
Access needed: Finance shared drive, QuickBooks, Office 365, VPN</p>
<p>He will need a laptop from the equipment room. Please also add him to the GRP-Finance-Staff and GRP-SharedDrive-RO groups initially — Raj will request elevated access separately if needed.</p>
<p>Thanks,<br>Sarah Williams<br>HR Manager</p>',
    '<p>Hi Sarah,</p>
<p>Thanks for the heads-up. I have started provisioning for Marcus Reed. Here is the current status:</p>
<ul>
<li>✅ AD account created: mreed@corp.local, temp password: Welc0me!2024</li>
<li>✅ Added to GRP-Finance-Staff and GRP-SharedDrive-RO</li>
<li>🔄 Office 365 license assignment — pending (waiting on license pool)</li>
<li>🔄 Laptop imaging in progress — Finance-WS-07 being reimaged</li>
<li>⬜ QuickBooks license — need approval from Raj Patel</li>
</ul>
<p>I will have everything ready by Friday EOD. Please have Marcus stop by the IT desk (Room 102) first thing Monday for setup and orientation.</p>
<p>— James Smith, IT Admin</p>'
);

-- ── TICKET 4 — Printer Not Responding (Closed) ───────────────
CALL seed_ticket(
    '100004',
    'Finance floor printer offline — HP LaserJet 400 M401',
    'bwashington@corp.local',
    'IT Helpdesk', 'Hardware', 'Normal - 8 Hours',
    2, 'closed', 'web',
    DATE_SUB(NOW(), INTERVAL 22 DAY),
    'tnguyen',
    '<p>Hello IT Support,</p>
<p>The printer on the Finance floor (3rd floor, near the copy room) has been showing as offline since this morning. Multiple people have tried printing and nothing is coming out. The printer shows a blinking orange light on the front panel.</p>
<p>Printer: HP LaserJet Pro 400 M401dne<br>
IP: 192.168.10.75<br>
Asset Tag: AST-2019-0042</p>
<p>Brian Washington<br>Accounts Payable</p>',
    '<p>Hi Brian,</p>
<p>I investigated the printer issue. Here is what I found and fixed:</p>
<p><strong>Root cause:</strong> The printer had a stuck print job in the queue from last night that was causing the spooler to hang. Additionally, the printer had rebooted overnight and received a new DHCP IP, breaking the static reservation.</p>
<p><strong>Actions taken:</strong></p>
<ol>
<li>Cleared print queue on the print server (PRINT01)</li>
<li>Restarted Print Spooler service on PRINT01</li>
<li>Updated DHCP reservation to lock 192.168.10.75 to this printer MAC address</li>
<li>Verified 10 test pages printed successfully</li>
</ol>
<p>The printer is back online. I have also set an alert in monitoring if the IP changes again.</p>
<p>— Tommy Nguyen, IT Helpdesk</p>'
);

-- ── TICKET 5 — Monitor Flickering (Open) ─────────────────────
CALL seed_ticket(
    '100005',
    'Monitor flickering and going black randomly — HR workstation',
    'lmartinez@corp.local',
    'IT Helpdesk', 'Hardware', 'Normal - 8 Hours',
    2, 'open', 'web',
    DATE_SUB(NOW(), INTERVAL 2 DAY),
    'alopez',
    '<p>Hi IT Team,</p>
<p>My monitor has been randomly flickering and going completely black for 2-3 seconds throughout the day. It started happening about a week ago and has gotten progressively worse. I have to move my mouse to get the display back. It is very disruptive during interviews and video calls.</p>
<p>My setup:<br>
Workstation: HR-WS-02<br>
Monitor: Dell 24" (Asset: AST-2020-0118)<br>
Connection type: HDMI<br>
OS: Windows 11</p>
<p>I have already tried restarting the computer — the issue persists.</p>
<p>Laura Martinez<br>Talent Acquisition</p>',
    '<p>Hi Laura,</p>
<p>Thank you for the detailed report. I will stop by HR-WS-02 this afternoon to investigate. In the meantime, could you check if the flickering happens with the monitor in its power-save "sleep" mode too, or only during active use?</p>
<p>Based on the symptoms, this is likely either a failing HDMI cable or a graphics driver issue. I will bring a replacement cable and check the driver version when I come by.</p>
<p>— Ana Lopez, IT Helpdesk</p>'
);

-- ── TICKET 6 — Laptop Won''t Boot (Resolved) ──────────────────
CALL seed_ticket(
    '100006',
    'Laptop not booting — black screen with cursor after Windows logo',
    'rpatel@corp.local',
    'IT Helpdesk', 'Hardware', 'High - 4 Hours',
    3, 'resolved', 'phone',
    DATE_SUB(NOW(), INTERVAL 18 DAY),
    'jsmith',
    '<p>My laptop stopped booting this morning. It shows the Windows logo briefly then goes to a black screen with only a mouse cursor visible. Nothing else loads. I have tried hard rebooting 3 times.</p>
<p>This is my primary work laptop — I have a board presentation this afternoon and need access to my files urgently.</p>
<p>Laptop: Dell Latitude 5520<br>
Asset: AST-2021-0007<br>
Username: rpatel</p>',
    '<p>Hi Raj,</p>
<p>I came to your desk and diagnosed the issue. The Windows shell (explorer.exe) was failing to start due to a corrupt user profile registry key, likely caused by a Windows Update that was applied mid-session last night.</p>
<p><strong>Resolution:</strong></p>
<ol>
<li>Booted into Safe Mode via F8</li>
<li>Ran: <code>sfc /scannow</code> — found and repaired 3 corrupted system files</li>
<li>Reset the shell registry key to the correct explorer.exe path</li>
<li>Normal boot successful</li>
<li>All files and applications confirmed accessible</li>
</ol>
<p>Your laptop is fully operational. I have documented this in our known issues log and will push the Windows Update policy change to prevent future mid-session updates.</p>
<p>Good luck with the presentation!</p>
<p>— James Smith, IT Admin</p>'
);

-- ── TICKET 7 — Teams Audio Issues (Closed) ───────────────────
CALL seed_ticket(
    '100007',
    'Microsoft Teams — no audio output during calls',
    'djohnson@corp.local',
    'IT Helpdesk', 'Software', 'Normal - 8 Hours',
    2, 'closed', 'web',
    DATE_SUB(NOW(), INTERVAL 14 DAY),
    'alopez',
    '<p>Hello IT,</p>
<p>Since the Teams update that was pushed last week, I cannot hear anything during calls. I can see that people are talking (the microphone icon shows activity) but no audio comes through my headset or speakers. My headset works fine on Zoom calls.</p>
<p>Teams version: 1.6.00.26474<br>
Headset: Jabra Evolve 40<br>
Workstation: HR-WS-04</p>
<p>This is really impacting my work — I have daily standup calls with the recruitment team.</p>
<p>David Johnson</p>',
    '<p>Hi David,</p>
<p>I have resolved the audio issue. After the recent Teams update (v1.6.00.26474), the default audio device was reset to the system default rather than your Jabra headset.</p>
<p><strong>Fix applied:</strong></p>
<ol>
<li>Opened Teams Settings > Devices</li>
<li>Set Speaker to: Jabra Evolve 40 (confirmed in Device Manager as well)</li>
<li>Set Microphone to: Jabra Evolve 40</li>
<li>Tested with a test call — audio working correctly in both directions</li>
</ol>
<p>This is a known issue with this Teams update. I will include a workaround note in the next IT bulletin so other users can self-service if they hit the same problem.</p>
<p>— Ana Lopez, IT Helpdesk</p>'
);

-- ── TICKET 8 — Excel Crashing (Open) ─────────────────────────
CALL seed_ticket(
    '100008',
    'Excel crashes when opening large .xlsx files — Finance shared drive',
    'kthompson@corp.local',
    'IT Helpdesk', 'Software', 'High - 4 Hours',
    3, 'open', 'web',
    DATE_SUB(NOW(), INTERVAL 1 DAY),
    'tnguyen',
    '<p>Hi IT Support,</p>
<p>Excel keeps crashing every time I try to open our Q4 financial model from the shared drive (Z:\Finance\Models\Q4_2024_Forecast.xlsx). The file is about 45MB with macros. It worked fine until 2 days ago.</p>
<p>The error I get is: <em>"Microsoft Excel has stopped working — Windows is looking for a solution"</em></p>
<p>I have tried:<br>
- Restarting Excel — same crash<br>
- Opening in Safe Mode (excel /safe) — same crash<br>
- Copying file locally first — crashes on the local copy too</p>
<p>I cannot miss our finance deadline on Friday. Can someone look at this urgently?</p>
<p>Karen Thompson<br>Senior Accountant</p>',
    '<p>Hi Karen,</p>
<p>I am looking into this now. A few questions to help me narrow it down:</p>
<ol>
<li>Did any Office updates get installed recently? (Check: File > Account > Update Options > View Updates)</li>
<li>Does the crash happen immediately on open, or after a specific action?</li>
<li>Can you open other .xlsx files without crashing?</li>
</ol>
<p>While you wait, please try this workaround:<br>
Open Excel first, then go to File > Open and navigate to the file. If it prompts about macros, click "Disable Macros" temporarily to see if the file opens without them.</p>
<p>I will remote in via MeshCentral to review your Office installation and event logs. Please let me know when you are at your desk.</p>
<p>— Tommy Nguyen, IT Helpdesk</p>'
);

-- ── TICKET 9 — Outlook Not Syncing (Closed) ──────────────────
CALL seed_ticket(
    '100009',
    'Outlook not receiving new emails — stuck at "Sending/Receiving"',
    'swilliams@corp.local',
    'IT Helpdesk', 'Software', 'Normal - 8 Hours',
    2, 'closed', 'email',
    DATE_SUB(NOW(), INTERVAL 10 DAY),
    'alopez',
    '<p>Good morning,</p>
<p>My Outlook has not received any new emails since yesterday afternoon. It shows "Send/Receive" progress bar at the bottom but never completes. I can send emails but nothing comes in. Webmail (OWA) works fine so the issue is just the desktop client.</p>
<p>I use Outlook 2021 on Windows 11.</p>
<p>Sarah Williams<br>HR Manager</p>',
    '<p>Hi Sarah,</p>
<p>Good news — I have resolved the sync issue. Your Outlook OST cache file had become corrupted, likely due to the unexpected shutdown on Tuesday (I can see it in the event logs).</p>
<p><strong>Steps taken:</strong></p>
<ol>
<li>Backed up your current OST file to C:\Users\swilliams\OST_backup_$(date)</li>
<li>Deleted the corrupt OST file</li>
<li>Re-launched Outlook — it rebuilt the cache from the Exchange server (took ~4 minutes)</li>
<li>Verified all folders syncing, including Sent Items and Calendar</li>
</ol>
<p>Everything should be current now. You may notice some emails appearing as "unread" that you had already read — this will correct itself as the sync completes.</p>
<p>Going forward, please use Start > Shut Down rather than the power button to prevent OST corruption.</p>
<p>— Ana Lopez, IT Helpdesk</p>'
);

-- ── TICKET 10 — Network Share Access (Open) ──────────────────
CALL seed_ticket(
    '100010',
    'Cannot access Z: drive — "Network path not found" error',
    'bwashington@corp.local',
    'Network Operations', 'Network', 'High - 4 Hours',
    3, 'open', 'phone',
    DATE_SUB(NOW(), INTERVAL 1 DAY),
    'mchen',
    '<p>Hi,</p>
<p>My Z: drive disappeared this morning. When I click on it I get the error: <em>"\\DC01\CompanyShare is not accessible. You might not have permission to use this network resource. The network path was not found."</em></p>
<p>I can ping DC01 (192.168.10.10) successfully. Other users on Finance seem to have the same issue — at least 2 coworkers reported the same thing this morning.</p>
<p>Brian Washington<br>Finance-WS-05</p>',
    '<p>Hi Brian,</p>
<p>Thank you for reporting this and flagging that multiple users are affected — this helps me prioritize. I am treating this as a potential service-impacting issue.</p>
<p>Initial investigation shows the SMB service on DC01 is running, and the share is visible from the server side. I suspect this may be a DNS or Kerberos ticket issue after last night''s DC maintenance window.</p>
<p><strong>Please try this while I investigate:</strong></p>
<pre>
1. Open Command Prompt as Administrator
2. Run: ipconfig /flushdns
3. Run: klist purge
4. Run: net use Z: /delete
5. Reboot your workstation
</pre>
<p>I am also checking the DC01 event logs for SMB errors. Will update within 30 minutes.</p>
<p>— Michael Chen, Network Operations</p>'
);

-- ── TICKET 11 — WiFi Dropping (Closed) ───────────────────────
CALL seed_ticket(
    '100011',
    'WiFi dropping every 15-20 minutes in Conference Room B',
    'rpatel@corp.local',
    'Network Operations', 'Network', 'Normal - 8 Hours',
    2, 'closed', 'web',
    DATE_SUB(NOW(), INTERVAL 20 DAY),
    'mchen',
    '<p>The WiFi in Conference Room B (2nd floor) is extremely unreliable. During our weekly Finance leadership meeting, my laptop and 3 others all drop WiFi simultaneously every 15-20 minutes. We have to reconnect each time which disrupts our meeting flow.</p>
<p>This has been happening for about 2 weeks. The hallway outside the room has fine WiFi. The issue seems specific to Conference Room B.</p>
<p>Raj Patel<br>Finance Director</p>',
    '<p>Hi Raj,</p>
<p>I have identified and resolved the WiFi issue in Conference Room B. Here is what I found:</p>
<p><strong>Root Cause:</strong> The access point covering Conference Room B (AP-2F-03, Ubiquiti UAP-AC-Pro) was experiencing a channel conflict with a neighboring AP (AP-2F-01). Both were set to the same 5GHz channel (channel 149). When the room is full of people with devices, the interference caused client drops every ~15-20 minutes — exactly what you described.</p>
<p><strong>Resolution:</strong></p>
<ol>
<li>Logged into Ubiquiti UniFi Controller</li>
<li>Changed AP-2F-03 from channel 149 to channel 161 (no overlap with nearby APs)</li>
<li>Reduced transmit power from High to Medium to reduce co-channel interference</li>
<li>Enabled band steering to push capable devices to 5GHz</li>
<li>Stress-tested with 8 concurrent devices for 45 minutes — no drops</li>
</ol>
<p>Conference Room B WiFi is now stable. I have also scheduled a full RF survey of the 2nd floor for next month to proactively address any other channel conflicts.</p>
<p>— Michael Chen, Network Operations</p>'
);

-- ── TICKET 12 — Slow Internet (Open) ─────────────────────────
CALL seed_ticket(
    '100012',
    'Internet extremely slow — pages timing out, affecting entire HR floor',
    'lmartinez@corp.local',
    'Network Operations', 'Network', 'High - 4 Hours',
    3, 'open', 'web',
    DATE_SUB(NOW(), INTERVAL 4 HOUR),
    'mchen',
    '<p>Hi IT,</p>
<p>The internet has been very slow or completely unavailable for the past hour on the HR floor (3rd floor). Web pages are timing out, Teams calls are dropping, and cloud file access is failing. Internal resources (intranet, shared drives) seem fine.</p>
<p>At least 6 people on my floor are affected. We have a candidate video interview in 30 minutes that requires internet access.</p>
<p>Speedtest from my workstation: 0.8 Mbps down / 0.2 Mbps up (normally ~500 Mbps)</p>
<p>Laura Martinez<br>HR-WS-06<br>IP: 192.168.30.45</p>',
    '<p>Hi Laura,</p>
<p>I am on it — this is a priority issue. Initial checks show that the WAN interface on our pfSense firewall is showing high packet loss (42%) to the upstream ISP gateway. This is likely an ISP-side issue or a problem with our border router.</p>
<p>I have opened a ticket with our ISP (CorpTech Fiber, ticket #ISP-88721) and I am monitoring the situation. Internal traffic is unaffected because it routes over our LAN only.</p>
<p><strong>For your interview in 30 minutes:</strong> I can enable failover to our 4G LTE backup connection for the HR floor VLAN immediately. Please confirm and I will activate it within 5 minutes.</p>
<p>— Michael Chen, Network Operations</p>'
);

-- ── TICKET 13 — VPN Access Request (Resolved) ────────────────
CALL seed_ticket(
    '100013',
    'VPN access request — need remote access to work from home',
    'swilliams@corp.local',
    'IT Helpdesk', 'Access Request', 'Normal - 8 Hours',
    2, 'resolved', 'web',
    DATE_SUB(NOW(), INTERVAL 15 DAY),
    'jsmith',
    '<p>Hello,</p>
<p>I need to request VPN access for remote work. I have approval from my manager and HR policy allows remote work 2 days per week for my role.</p>
<p>I will be using a company-managed laptop (HR-LT-03, Asset: AST-2022-0055).</p>
<p>Please let me know what I need to install and any configuration steps.</p>
<p>Thank you,<br>Sarah Williams<br>HR Manager</p>',
    '<p>Hi Sarah,</p>
<p>VPN access has been provisioned for your account. Here are your setup instructions:</p>
<p><strong>VPN Client Setup (OpenVPN):</strong></p>
<ol>
<li>Download the VPN client: \\DC01\CompanyShare\IT\VPN-Client-Setup.exe</li>
<li>Install with default settings</li>
<li>Import config: \\DC01\CompanyShare\IT\VPN-Configs\swilliams-vpn.ovpn</li>
<li>Connect using your domain credentials (swilliams / your AD password)</li>
<li>MFA is required — you will receive a push notification to your registered phone</li>
</ol>
<p><strong>What VPN gives you access to:</strong> Company intranet, shared drives (Z:), internal applications</p>
<p>I have also added you to the GRP-VPN-Users security group in AD. Please test the connection and let me know if you need help.</p>
<p>— James Smith, IT Admin</p>'
);

-- ── TICKET 14 — BSOD (Open) ──────────────────────────────────
CALL seed_ticket(
    '100014',
    'Blue screen of death — DRIVER_IRQL_NOT_LESS_OR_EQUAL — recurring',
    'djohnson@corp.local',
    'IT Helpdesk', 'Hardware', 'High - 4 Hours',
    3, 'open', 'phone',
    DATE_SUB(NOW(), INTERVAL 6 HOUR),
    'jsmith',
    '<p>My computer keeps crashing with a blue screen. It has happened 4 times today already. The error code shown is: <strong>DRIVER_IRQL_NOT_LESS_OR_EQUAL</strong>. After the crash, Windows restarts automatically.</p>
<p>The crashes seem to happen when I am using Chrome with multiple tabs open, but I am not 100% sure.</p>
<p>Workstation: HR-WS-04<br>
OS: Windows 11 22H2<br>
RAM: 8GB<br>
Last Windows Update: 3 days ago</p>
<p>I have important HR documents I was working on — are they at risk?</p>
<p>David Johnson</p>',
    '<p>Hi David,</p>
<p>I am sorry to hear about the crashes — DRIVER_IRQL_NOT_LESS_OR_EQUAL usually points to a faulty or incompatible driver, which is fixable. Your files are not at risk as long as you save frequently (Ctrl+S).</p>
<p>I will remote in via MeshCentral to collect the minidump files from C:\Windows\Minidump\ and analyze them with WinDbg. This will tell us exactly which driver is causing the crash.</p>
<p><strong>In the meantime:</strong></p>
<ul>
<li>Save your work every few minutes to Z:\HR\ (auto-sync to server)</li>
<li>If comfortable, try using Edge instead of Chrome temporarily</li>
<li>Note the exact time of each crash so I can correlate with event logs</li>
</ul>
<p>I will have a diagnosis within 2 hours.</p>
<p>— James Smith, IT Admin</p>'
);

-- ── TICKET 15 — Software Install Request (Closed) ────────────
CALL seed_ticket(
    '100015',
    'Software installation request — Adobe Acrobat Pro for Finance',
    'kthompson@corp.local',
    'IT Helpdesk', 'Software', 'Normal - 8 Hours',
    2, 'closed', 'web',
    DATE_SUB(NOW(), INTERVAL 12 DAY),
    'tnguyen',
    '<p>Hi IT Team,</p>
<p>I need Adobe Acrobat Pro installed on my workstation. I regularly receive digitally-signed PDF contracts from vendors that need to be verified and stamped with our company seal. Adobe Reader does not support these features.</p>
<p>I have confirmed with Raj Patel (Finance Director) that this is a business requirement and he has approved the purchase or use of an existing license.</p>
<p>Workstation: Finance-WS-02<br>
Username: kthompson</p>
<p>Karen Thompson<br>Senior Accountant</p>',
    '<p>Hi Karen,</p>
<p>Adobe Acrobat Pro has been installed on Finance-WS-02. Here are the details:</p>
<p><strong>Installation Summary:</strong></p>
<ul>
<li>Application: Adobe Acrobat Pro DC (version 24.x)</li>
<li>License: Assigned from our enterprise pool (License #ACR-ENT-0047)</li>
<li>Installation method: Silent deploy via PDQ Deploy — no reboot required</li>
<li>Activation: Automatic via Adobe enterprise license server</li>
</ul>
<p>The application is ready in your Start Menu. You may need to sign in with your Adobe ID (use your corp.local email address) on first launch — IT has pre-configured the SSO for this.</p>
<p>I have also updated the asset register to reflect this license assignment. Let me know if you need any training resources for the digital signature features.</p>
<p>— Tommy Nguyen, IT Helpdesk</p>'
);

-- ── Cleanup ───────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS seed_ticket;

-- ── Verification query ────────────────────────────────────────
SELECT
    t.number,
    t.subject,
    CONCAT(u.name)                                         AS requester,
    CONCAT(s.firstname, ' ', s.lastname)                   AS assigned_to,
    d.name                                                 AS department,
    ht.topic                                               AS category,
    ts.name                                                AS status,
    t.created
FROM ost_ticket t
JOIN ost_user          u  ON u.id         = t.user_id
JOIN ost_department    d  ON d.id         = t.dept_id
JOIN ost_help_topic    ht ON ht.id        = t.topic_id
JOIN ost_ticket_status ts ON ts.id        = t.status_id
LEFT JOIN ost_staff    s  ON s.staff_id   = t.staff_id
ORDER BY t.number;
