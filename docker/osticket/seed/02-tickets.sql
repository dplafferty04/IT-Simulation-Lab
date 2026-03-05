-- ============================================================
-- osTicket Seed: 15 Realistic Helpdesk Tickets
-- Target: osTicket v1.17.5 (devinsolutions image)
-- Subject stored in ost_ticket__cdata (v1.15+ schema)
-- ============================================================

USE osticket;

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
    IN p_status      VARCHAR(20),
    IN p_source      VARCHAR(32),
    IN p_created     DATETIME,
    IN p_agent_user  VARCHAR(64),
    IN p_body        TEXT,
    IN p_reply       TEXT
)
sp_body: BEGIN
    DECLARE v_user_id     INT DEFAULT 0;
    DECLARE v_email_id    INT DEFAULT 0;
    DECLARE v_dept_id     INT DEFAULT 0;
    DECLARE v_topic_id    INT DEFAULT 0;
    DECLARE v_sla_id      INT DEFAULT 0;
    DECLARE v_staff_id    INT DEFAULT 0;
    DECLARE v_status_id   INT DEFAULT 1;
    DECLARE v_ticket_id   INT DEFAULT 0;
    DECLARE v_thread_id   INT DEFAULT 0;
    DECLARE v_source_norm VARCHAR(32);
    DECLARE v_reply_time  DATETIME;

    -- Skip if ticket already exists
    IF EXISTS (SELECT 1 FROM ost_ticket WHERE number = p_number) THEN
        LEAVE sp_body;
    END IF;

    -- Normalize source to match enum('Web','Email','Phone','API','Other')
    SET v_source_norm = CASE LOWER(p_source)
        WHEN 'web'   THEN 'Web'
        WHEN 'email' THEN 'Email'
        WHEN 'phone' THEN 'Phone'
        WHEN 'api'   THEN 'API'
        ELSE 'Other'
    END;

    -- Lookups
    SELECT ue.user_id, ue.id INTO v_user_id, v_email_id
    FROM ost_user_email ue WHERE ue.address = p_user_email LIMIT 1;

    SELECT id      INTO v_dept_id  FROM ost_department WHERE name  = p_dept_name  LIMIT 1;
    SELECT topic_id INTO v_topic_id FROM ost_help_topic WHERE topic = p_topic_name LIMIT 1;
    SELECT id      INTO v_sla_id   FROM ost_sla         WHERE name  = p_sla_name   LIMIT 1;
    SELECT staff_id INTO v_staff_id FROM ost_staff       WHERE username = p_agent_user LIMIT 1;

    SELECT id INTO v_status_id FROM ost_ticket_status
    WHERE LOWER(name) = LOWER(p_status) LIMIT 1;
    IF v_status_id = 0 THEN SET v_status_id = 1; END IF;

    SET v_reply_time = DATE_ADD(p_created, INTERVAL 45 MINUTE);

    -- Insert ticket (subject goes to ost_ticket__cdata)
    INSERT INTO ost_ticket
        (number, user_id, user_email_id, status_id, dept_id, sla_id, topic_id,
         staff_id, team_id, source, ip_address, flags, isoverdue,
         created, updated, lastupdate,
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
        0,
        v_source_norm,
        '10.10.10.1',
        0,
        0,
        p_created,
        p_created,
        p_created,
        DATE_ADD(p_created, INTERVAL 8 HOUR),
        IF(p_status IN ('resolved','closed'), DATE_ADD(p_created, INTERVAL 2 HOUR), NULL)
    );

    SET v_ticket_id = LAST_INSERT_ID();

    -- Store subject in cdata table
    INSERT INTO ost_ticket__cdata (ticket_id, subject)
    VALUES (v_ticket_id, p_subject)
    ON DUPLICATE KEY UPDATE subject = p_subject;

    -- Create thread
    INSERT INTO ost_thread (object_id, object_type, extra,
        lastmessage, lastresponse, created)
    VALUES (
        v_ticket_id, 'T', '{}',
        p_created,
        IF(p_reply IS NOT NULL, v_reply_time, NULL),
        p_created
    );

    SET v_thread_id = LAST_INSERT_ID();

    -- Initial user message
    INSERT INTO ost_thread_entry
        (thread_id, staff_id, user_id, type, flags, source, format,
         title, body, created, updated, poster)
    VALUES (
        v_thread_id,
        0,
        v_user_id,
        'M',
        0,
        v_source_norm,
        'html',
        p_subject,
        p_body,
        p_created,
        p_created,
        (SELECT name FROM ost_user WHERE id = v_user_id LIMIT 1)
    );

    -- Agent reply
    IF p_reply IS NOT NULL AND v_staff_id > 0 THEN
        INSERT INTO ost_thread_entry
            (thread_id, staff_id, user_id, type, flags, source, format,
             title, body, created, updated, poster)
        VALUES (
            v_thread_id,
            v_staff_id,
            0,
            'R',
            0,
            'Web',
            'html',
            CONCAT('Re: ', p_subject),
            p_reply,
            v_reply_time,
            v_reply_time,
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
<p><strong>Action taken:</strong> Account unlocked via AD Users &amp; Computers. Cleared saved credentials on Finance-WS-02 remotely.</p>
<p>Please try logging in now. I would also recommend updating any saved passwords in your browser or applications.</p>
<p>— Tommy Nguyen, IT Helpdesk</p>'
);

-- ── TICKET 3 — New User Setup (Open) ─────────────────────────
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
Name: Marcus Reed<br>Title: Junior Accountant<br>Department: Finance<br>Start Date: Monday<br>
Access needed: Finance shared drive, QuickBooks, Office 365, VPN</p>
<p>Thanks,<br>Sarah Williams<br>HR Manager</p>',
    '<p>Hi Sarah,</p>
<p>Thanks for the heads-up. I have started provisioning for Marcus Reed:</p>
<ul>
<li>[DONE] AD account created: mreed@corp.local</li>
<li>[DONE] Added to GRP-Finance-Staff and GRP-SharedDrive-RO</li>
<li>[IN PROGRESS] Office 365 license — pending</li>
<li>[IN PROGRESS] Laptop imaging in progress — Finance-WS-07</li>
<li>[PENDING] QuickBooks license — need approval from Raj Patel</li>
</ul>
<p>Everything will be ready by Friday EOD. Have Marcus stop by IT (Room 102) Monday morning.</p>
<p>— James Smith, IT Admin</p>'
);

-- ── TICKET 4 — Printer Offline (Closed) ──────────────────────
CALL seed_ticket(
    '100004',
    'Finance floor printer offline — HP LaserJet 400 M401',
    'bwashington@corp.local',
    'IT Helpdesk', 'Hardware', 'Normal - 8 Hours',
    2, 'closed', 'web',
    DATE_SUB(NOW(), INTERVAL 22 DAY),
    'tnguyen',
    '<p>Hello IT Support,</p>
<p>The printer on the Finance floor (3rd floor, near the copy room) has been showing as offline since this morning. Multiple people have tried printing and nothing is coming out.</p>
<p>Printer: HP LaserJet Pro 400 M401dne<br>IP: 192.168.10.75<br>Asset Tag: AST-2019-0042</p>
<p>Brian Washington<br>Accounts Payable</p>',
    '<p>Hi Brian,</p>
<p><strong>Root cause:</strong> Stuck print job in the queue caused the spooler to hang. The printer also received a new DHCP IP overnight, breaking the static reservation.</p>
<p><strong>Actions taken:</strong></p>
<ol>
<li>Cleared print queue on PRINT01</li>
<li>Restarted Print Spooler service</li>
<li>Updated DHCP reservation to lock 192.168.10.75 to this printer MAC</li>
<li>Verified 10 test pages printed successfully</li>
</ol>
<p>Printer is back online.</p>
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
<p>My monitor has been randomly flickering and going completely black for 2-3 seconds throughout the day. It started about a week ago and is getting worse. Very disruptive during video calls.</p>
<p>Workstation: HR-WS-02<br>Monitor: Dell 24" (Asset: AST-2020-0118)<br>Connection: HDMI<br>OS: Windows 11</p>
<p>Laura Martinez<br>Talent Acquisition</p>',
    '<p>Hi Laura,</p>
<p>I will stop by HR-WS-02 this afternoon. Based on the symptoms this is likely a failing HDMI cable or a graphics driver issue. I will bring a replacement cable.</p>
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
    '<p>My laptop stopped booting this morning. It shows the Windows logo briefly then goes to a black screen with only a mouse cursor. I have a board presentation this afternoon and need access urgently.</p>
<p>Laptop: Dell Latitude 5520<br>Asset: AST-2021-0007<br>Username: rpatel</p>',
    '<p>Hi Raj,</p>
<p>Diagnosed and resolved. The Windows shell (explorer.exe) was failing due to a corrupt user profile registry key from a Windows Update applied mid-session.</p>
<p><strong>Resolution:</strong></p>
<ol>
<li>Booted into Safe Mode</li>
<li>Ran sfc /scannow — repaired 3 corrupted system files</li>
<li>Reset shell registry key to correct explorer.exe path</li>
<li>Normal boot successful — all files accessible</li>
</ol>
<p>Good luck with the presentation!</p>
<p>— James Smith, IT Admin</p>'
);

-- ── TICKET 7 — Teams Audio (Closed) ──────────────────────────
CALL seed_ticket(
    '100007',
    'Microsoft Teams — no audio output during calls',
    'djohnson@corp.local',
    'IT Helpdesk', 'Software', 'Normal - 8 Hours',
    2, 'closed', 'web',
    DATE_SUB(NOW(), INTERVAL 14 DAY),
    'alopez',
    '<p>Hello IT,</p>
<p>Since the Teams update last week, I cannot hear anything during calls. My headset works fine on Zoom.</p>
<p>Teams version: 1.6.00.26474<br>Headset: Jabra Evolve 40<br>Workstation: HR-WS-04</p>
<p>David Johnson</p>',
    '<p>Hi David,</p>
<p>Resolved. After the recent Teams update the default audio device was reset to the system default rather than your Jabra headset.</p>
<p><strong>Fix:</strong> Teams Settings &gt; Devices — set Speaker and Microphone to Jabra Evolve 40. Tested with a test call — working correctly.</p>
<p>This is a known issue with this update. I will include a workaround in the next IT bulletin.</p>
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
<p>Excel crashes every time I try to open our Q4 financial model (Z:\Finance\Models\Q4_2024_Forecast.xlsx, ~45MB with macros). Error: "Microsoft Excel has stopped working".</p>
<p>I have tried restarting, Safe Mode, and copying locally — same crash. Cannot miss our Friday finance deadline.</p>
<p>Karen Thompson<br>Senior Accountant</p>',
    '<p>Hi Karen,</p>
<p>Looking into this now. While I investigate, please try: open Excel first, then File &gt; Open and navigate to the file — if prompted about macros, click Disable Macros temporarily.</p>
<p>I will remote in via MeshCentral to review your Office installation and event logs. Let me know when you are at your desk.</p>
<p>— Tommy Nguyen, IT Helpdesk</p>'
);

-- ── TICKET 9 — Outlook Not Syncing (Closed) ───────────────────
CALL seed_ticket(
    '100009',
    'Outlook not receiving new emails — stuck at "Sending/Receiving"',
    'swilliams@corp.local',
    'IT Helpdesk', 'Software', 'Normal - 8 Hours',
    2, 'closed', 'email',
    DATE_SUB(NOW(), INTERVAL 10 DAY),
    'alopez',
    '<p>Good morning,</p>
<p>My Outlook has not received any new emails since yesterday afternoon. It shows the Send/Receive progress bar but never completes. Webmail (OWA) works fine — issue is just the desktop client.</p>
<p>Sarah Williams<br>HR Manager</p>',
    '<p>Hi Sarah,</p>
<p>Resolved. Your Outlook OST cache file was corrupted, likely due to the unexpected shutdown on Tuesday.</p>
<p><strong>Steps taken:</strong></p>
<ol>
<li>Backed up OST file</li>
<li>Deleted corrupt OST file</li>
<li>Re-launched Outlook — rebuilt cache from Exchange (~4 minutes)</li>
<li>Verified all folders syncing</li>
</ol>
<p>Going forward, please use Start &gt; Shut Down rather than the power button.</p>
<p>— Ana Lopez, IT Helpdesk</p>'
);

-- ── TICKET 10 — Network Share Access (Open) ───────────────────
CALL seed_ticket(
    '100010',
    'Cannot access Z: drive — "Network path not found" error',
    'bwashington@corp.local',
    'Network Operations', 'Network', 'High - 4 Hours',
    3, 'open', 'phone',
    DATE_SUB(NOW(), INTERVAL 1 DAY),
    'mchen',
    '<p>Hi,</p>
<p>My Z: drive disappeared this morning. Error: "\\DC01\CompanyShare is not accessible. The network path was not found." At least 2 coworkers on Finance have the same issue.</p>
<p>Brian Washington<br>Finance-WS-05</p>',
    '<p>Hi Brian,</p>
<p>Treating this as a service-impacting issue. The SMB service on DC01 is running — I suspect a DNS or Kerberos ticket issue after last night''s maintenance window.</p>
<p><strong>Please try while I investigate:</strong></p>
<pre>1. Open CMD as Administrator
2. ipconfig /flushdns
3. klist purge
4. net use Z: /delete
5. Reboot</pre>
<p>Will update within 30 minutes.</p>
<p>— Michael Chen, Network Operations</p>'
);

-- ── TICKET 11 — WiFi Dropping (Closed) ────────────────────────
CALL seed_ticket(
    '100011',
    'WiFi dropping every 15-20 minutes in Conference Room B',
    'rpatel@corp.local',
    'Network Operations', 'Network', 'Normal - 8 Hours',
    2, 'closed', 'web',
    DATE_SUB(NOW(), INTERVAL 20 DAY),
    'mchen',
    '<p>The WiFi in Conference Room B (2nd floor) is extremely unreliable. During our weekly Finance leadership meeting, 4 laptops all drop WiFi simultaneously every 15-20 minutes.</p>
<p>This has been happening for about 2 weeks. The hallway outside has fine WiFi.</p>
<p>Raj Patel<br>Finance Director</p>',
    '<p>Hi Raj,</p>
<p><strong>Root Cause:</strong> AP-2F-03 (Ubiquiti UAP-AC-Pro) had a channel conflict with AP-2F-01 — both on 5GHz channel 149. With a full room of devices the interference caused drops every ~15-20 minutes.</p>
<p><strong>Resolution:</strong></p>
<ol>
<li>Changed AP-2F-03 from channel 149 to channel 161</li>
<li>Reduced transmit power from High to Medium</li>
<li>Enabled band steering</li>
<li>Stress-tested 8 devices for 45 minutes — no drops</li>
</ol>
<p>Conference Room B WiFi is now stable.</p>
<p>— Michael Chen, Network Operations</p>'
);

-- ── TICKET 12 — Slow Internet (Open) ──────────────────────────
CALL seed_ticket(
    '100012',
    'Internet extremely slow — pages timing out, affecting entire HR floor',
    'lmartinez@corp.local',
    'Network Operations', 'Network', 'High - 4 Hours',
    3, 'open', 'web',
    DATE_SUB(NOW(), INTERVAL 4 HOUR),
    'mchen',
    '<p>Hi IT,</p>
<p>Internet has been very slow or unavailable for the past hour on the HR floor. Web pages are timing out, Teams calls dropping. Internal resources seem fine. At least 6 people affected.</p>
<p>Speedtest: 0.8 Mbps down (normally ~500 Mbps)</p>
<p>Laura Martinez<br>HR-WS-06 / 192.168.30.45</p>',
    '<p>Hi Laura,</p>
<p>On it — the WAN interface on our pfSense firewall is showing 42% packet loss to the upstream ISP gateway. I have opened a ticket with our ISP (ticket #ISP-88721).</p>
<p>I can enable failover to our 4G LTE backup for the HR VLAN immediately for your interview in 30 minutes. Please confirm and I will activate within 5 minutes.</p>
<p>— Michael Chen, Network Operations</p>'
);

-- ── TICKET 13 — VPN Access Request (Resolved) ─────────────────
CALL seed_ticket(
    '100013',
    'VPN access request — need remote access to work from home',
    'swilliams@corp.local',
    'IT Helpdesk', 'Access Request', 'Normal - 8 Hours',
    2, 'resolved', 'web',
    DATE_SUB(NOW(), INTERVAL 15 DAY),
    'jsmith',
    '<p>Hello,</p>
<p>I need to request VPN access for remote work. I have manager approval and HR policy allows remote work 2 days per week for my role. I will be using company laptop HR-LT-03 (Asset: AST-2022-0055).</p>
<p>Sarah Williams<br>HR Manager</p>',
    '<p>Hi Sarah,</p>
<p>VPN access provisioned. Setup instructions:</p>
<ol>
<li>Download VPN client: \\DC01\CompanyShare\IT\VPN-Client-Setup.exe</li>
<li>Install with default settings</li>
<li>Import config: \\DC01\CompanyShare\IT\VPN-Configs\swilliams-vpn.ovpn</li>
<li>Connect using your domain credentials</li>
<li>MFA required — push notification to your registered phone</li>
</ol>
<p>You have been added to GRP-VPN-Users in AD. Test the connection and let me know if you need help.</p>
<p>— James Smith, IT Admin</p>'
);

-- ── TICKET 14 — BSOD (Open) ───────────────────────────────────
CALL seed_ticket(
    '100014',
    'Blue screen of death — DRIVER_IRQL_NOT_LESS_OR_EQUAL — recurring',
    'djohnson@corp.local',
    'IT Helpdesk', 'Hardware', 'High - 4 Hours',
    3, 'open', 'phone',
    DATE_SUB(NOW(), INTERVAL 6 HOUR),
    'jsmith',
    '<p>My computer keeps crashing with a blue screen. It has happened 4 times today. Error: <strong>DRIVER_IRQL_NOT_LESS_OR_EQUAL</strong>. Crashes seem to happen with Chrome open with multiple tabs.</p>
<p>Workstation: HR-WS-04<br>OS: Windows 11 22H2<br>RAM: 8GB<br>Last Windows Update: 3 days ago</p>
<p>David Johnson</p>',
    '<p>Hi David,</p>
<p>DRIVER_IRQL_NOT_LESS_OR_EQUAL usually points to a faulty driver — fixable. Your files are safe as long as you save frequently (Ctrl+S).</p>
<p>I will remote in via MeshCentral to collect the minidump files from C:\Windows\Minidump\ and analyze with WinDbg.</p>
<p><strong>In the meantime:</strong> save work to Z:\HR\, try Edge instead of Chrome, and note the time of each crash.</p>
<p>— James Smith, IT Admin</p>'
);

-- ── TICKET 15 — Software Install (Closed) ─────────────────────
CALL seed_ticket(
    '100015',
    'Software installation request — Adobe Acrobat Pro for Finance',
    'kthompson@corp.local',
    'IT Helpdesk', 'Software', 'Normal - 8 Hours',
    2, 'closed', 'web',
    DATE_SUB(NOW(), INTERVAL 12 DAY),
    'tnguyen',
    '<p>Hi IT Team,</p>
<p>I need Adobe Acrobat Pro installed on Finance-WS-02. I regularly receive digitally-signed PDF contracts that require verification and stamping — Adobe Reader does not support these features.</p>
<p>Raj Patel (Finance Director) has approved the license use.</p>
<p>Karen Thompson<br>Senior Accountant</p>',
    '<p>Hi Karen,</p>
<p>Adobe Acrobat Pro DC installed on Finance-WS-02.</p>
<ul>
<li>Version: Adobe Acrobat Pro DC (24.x)</li>
<li>License: Enterprise pool (License #ACR-ENT-0047)</li>
<li>Deployed via PDQ Deploy — no reboot required</li>
<li>SSO pre-configured for corp.local accounts</li>
</ul>
<p>Ready in your Start Menu. Sign in with your corp.local email on first launch.</p>
<p>— Tommy Nguyen, IT Helpdesk</p>'
);

-- ── Cleanup ───────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS seed_ticket;

-- ── Verification ──────────────────────────────────────────────
SELECT
    t.number        AS `#`,
    cd.subject      AS `Subject`,
    u.name          AS `Requester`,
    CONCAT(s.firstname, ' ', s.lastname) AS `Agent`,
    d.name          AS `Department`,
    ts.name         AS `Status`,
    t.created       AS `Created`
FROM ost_ticket t
JOIN ost_ticket__cdata cd ON cd.ticket_id  = t.ticket_id
JOIN ost_user           u  ON u.id          = t.user_id
JOIN ost_department     d  ON d.id          = t.dept_id
JOIN ost_ticket_status  ts ON ts.id         = t.status_id
LEFT JOIN ost_staff     s  ON s.staff_id    = t.staff_id
ORDER BY t.number;
