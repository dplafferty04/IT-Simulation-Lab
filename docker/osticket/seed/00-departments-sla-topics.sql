-- ============================================================
-- osTicket Seed: Departments, SLA Plans, Help Topics
-- Target: osTicket v1.17.x / v1.18.x
-- Run AFTER the web installer completes.
-- ============================================================

USE osticket;

-- ── SLA Plans ────────────────────────────────────────────────
-- grace_period = hours before ticket is marked overdue
-- flags: 2 = transient (auto-close when resolved), bit 3 = enable

INSERT INTO ost_sla (name, grace_period, flags, notes, created, updated)
SELECT 'Critical - 1 Hour', 1, 3,
    'P1: System outage, security incident, or complete work stoppage for multiple users.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_sla WHERE name = 'Critical - 1 Hour');

INSERT INTO ost_sla (name, grace_period, flags, notes, created, updated)
SELECT 'High - 4 Hours', 4, 3,
    'P2: Significant impact to a single user or small group. No workaround available.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_sla WHERE name = 'High - 4 Hours');

INSERT INTO ost_sla (name, grace_period, flags, notes, created, updated)
SELECT 'Normal - 8 Hours', 8, 3,
    'P3: Standard helpdesk request. Workaround exists or impact is limited.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_sla WHERE name = 'Normal - 8 Hours');

INSERT INTO ost_sla (name, grace_period, flags, notes, created, updated)
SELECT 'Low - 24 Hours', 24, 3,
    'P4: Minor issue, cosmetic, or informational request.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_sla WHERE name = 'Low - 24 Hours');

-- ── Departments ───────────────────────────────────────────────
-- flags: 1 = active, 2 = public
-- ispublic is set in the flags bitmask in newer versions, but
-- some versions use a separate ispublic column — we set both.

INSERT INTO ost_department
    (pid, tpl_id, sla_id, name, `signature`, ispublic, email_id,
     autoresp_email_id, flags, created, updated)
SELECT
    0,                                              -- pid (root dept)
    0,                                              -- tpl_id (default template)
    (SELECT id FROM ost_sla WHERE name = 'Normal - 8 Hours' LIMIT 1),
    'IT Helpdesk',
    'CorpTech IT Helpdesk\nPhone: ext. 5900 | Email: helpdesk@corp.local\nhttps://helpdesk.corp.local',
    1,                                              -- ispublic
    0,                                              -- email_id (uses system default)
    0,
    1,                                              -- flags: active
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_department WHERE name = 'IT Helpdesk');

INSERT INTO ost_department
    (pid, tpl_id, sla_id, name, `signature`, ispublic, email_id,
     autoresp_email_id, flags, created, updated)
SELECT
    0,
    0,
    (SELECT id FROM ost_sla WHERE name = 'High - 4 Hours' LIMIT 1),
    'Network Operations',
    'CorpTech Network Operations\nPhone: ext. 5910 | Email: netops@corp.local\n24/7 NOC: ext. 5911',
    1,
    0,
    0,
    1,
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_department WHERE name = 'Network Operations');

-- ── Help Topics (Ticket Categories) ──────────────────────────
-- Each topic belongs to a department and has a default SLA.
-- pid = 0 means top-level topic.

-- Top-level categories
INSERT INTO ost_help_topic
    (isactive, ispublic, noautoresp, pid, sla_id, dept_id, topic, note, created, updated)
SELECT
    1, 1, 0, 0,
    (SELECT id FROM ost_sla WHERE name = 'Normal - 8 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    'Account Issues',
    'Password resets, account lockouts, new user setup, permissions.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'Account Issues');

INSERT INTO ost_help_topic
    (isactive, ispublic, noautoresp, pid, sla_id, dept_id, topic, note, created, updated)
SELECT
    1, 1, 0, 0,
    (SELECT id FROM ost_sla WHERE name = 'Normal - 8 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    'Hardware',
    'Physical equipment issues: computers, monitors, printers, peripherals.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'Hardware');

INSERT INTO ost_help_topic
    (isactive, ispublic, noautoresp, pid, sla_id, dept_id, topic, note, created, updated)
SELECT
    1, 1, 0, 0,
    (SELECT id FROM ost_sla WHERE name = 'Normal - 8 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    'Software',
    'Application errors, installation requests, licensing.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'Software');

INSERT INTO ost_help_topic
    (isactive, ispublic, noautoresp, pid, sla_id, dept_id, topic, note, created, updated)
SELECT
    1, 1, 0, 0,
    (SELECT id FROM ost_sla WHERE name = 'High - 4 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'Network Operations' LIMIT 1),
    'Network',
    'Connectivity, VPN, WiFi, firewall, and DNS issues.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'Network');

-- Sub-topics under Account Issues
INSERT INTO ost_help_topic
    (isactive, ispublic, noautoresp, pid, sla_id, dept_id, topic, note, created, updated)
SELECT
    1, 1, 0,
    (SELECT id FROM ost_help_topic WHERE topic = 'Account Issues' LIMIT 1),
    (SELECT id FROM ost_sla WHERE name = 'High - 4 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    'Password Reset',
    'User cannot log in, forgot password, or password expired.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'Password Reset');

INSERT INTO ost_help_topic
    (isactive, ispublic, noautoresp, pid, sla_id, dept_id, topic, note, created, updated)
SELECT
    1, 1, 0,
    (SELECT id FROM ost_help_topic WHERE topic = 'Account Issues' LIMIT 1),
    (SELECT id FROM ost_sla WHERE name = 'High - 4 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    'Account Lockout',
    'Account locked after multiple failed login attempts.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'Account Lockout');

INSERT INTO ost_help_topic
    (isactive, ispublic, noautoresp, pid, sla_id, dept_id, topic, note, created, updated)
SELECT
    1, 1, 0,
    (SELECT id FROM ost_help_topic WHERE topic = 'Account Issues' LIMIT 1),
    (SELECT id FROM ost_sla WHERE name = 'Normal - 8 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    'New User Setup',
    'Onboarding a new employee — account creation, equipment, access.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'New User Setup');

INSERT INTO ost_help_topic
    (isactive, ispublic, noautoresp, pid, sla_id, dept_id, topic, note, created, updated)
SELECT
    1, 1, 0,
    (SELECT id FROM ost_help_topic WHERE topic = 'Account Issues' LIMIT 1),
    (SELECT id FROM ost_sla WHERE name = 'Normal - 8 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    'Access Request',
    'Request for access to a system, share, or application.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'Access Request');

-- Verify
SELECT 'SLA Plans' AS section, name, grace_period AS hours FROM ost_sla
UNION ALL
SELECT 'Departments', name, NULL FROM ost_department
UNION ALL
SELECT 'Help Topics', topic, NULL FROM ost_help_topic
ORDER BY section, name;
