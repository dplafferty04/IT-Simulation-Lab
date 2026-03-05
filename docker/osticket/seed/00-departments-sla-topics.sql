-- ============================================================
-- osTicket Seed: Departments, SLA Plans, Help Topics
-- Target: osTicket v1.17.5 (devinsolutions image)
-- Run AFTER the web installer completes.
-- ============================================================

USE osticket;

-- ── SLA Plans ────────────────────────────────────────────────

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

INSERT INTO ost_department
    (pid, tpl_id, sla_id, name, `signature`, ispublic, email_id,
     autoresp_email_id, flags, created, updated)
SELECT
    0,
    0,
    (SELECT id FROM ost_sla WHERE name = 'Normal - 8 Hours' LIMIT 1),
    'IT Helpdesk',
    'CorpTech IT Helpdesk\nPhone: ext. 5900 | Email: helpdesk@corp.local',
    1,
    0,
    0,
    1,
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
    'CorpTech Network Operations\nPhone: ext. 5910 | Email: netops@corp.local',
    1,
    0,
    0,
    1,
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_department WHERE name = 'Network Operations');

-- ── Help Topics ───────────────────────────────────────────────
-- v1.17.x schema: topic_pid (not pid), notes (not note), no isactive column

INSERT INTO ost_help_topic
    (ispublic, noautoresp, topic_pid, sla_id, dept_id, topic, notes, created, updated)
SELECT
    1, 0, 0,
    (SELECT id FROM ost_sla WHERE name = 'Normal - 8 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    'Account Issues',
    'Password resets, account lockouts, new user setup, permissions.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'Account Issues');

INSERT INTO ost_help_topic
    (ispublic, noautoresp, topic_pid, sla_id, dept_id, topic, notes, created, updated)
SELECT
    1, 0, 0,
    (SELECT id FROM ost_sla WHERE name = 'Normal - 8 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    'Hardware',
    'Physical equipment issues: computers, monitors, printers, peripherals.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'Hardware');

INSERT INTO ost_help_topic
    (ispublic, noautoresp, topic_pid, sla_id, dept_id, topic, notes, created, updated)
SELECT
    1, 0, 0,
    (SELECT id FROM ost_sla WHERE name = 'Normal - 8 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    'Software',
    'Application errors, installation requests, licensing.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'Software');

INSERT INTO ost_help_topic
    (ispublic, noautoresp, topic_pid, sla_id, dept_id, topic, notes, created, updated)
SELECT
    1, 0, 0,
    (SELECT id FROM ost_sla WHERE name = 'High - 4 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'Network Operations' LIMIT 1),
    'Network',
    'Connectivity, VPN, WiFi, firewall, and DNS issues.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'Network');

-- Sub-topics under Account Issues
INSERT INTO ost_help_topic
    (ispublic, noautoresp, topic_pid, sla_id, dept_id, topic, notes, created, updated)
SELECT
    1, 0,
    (SELECT topic_id FROM ost_help_topic WHERE topic = 'Account Issues' LIMIT 1),
    (SELECT id FROM ost_sla WHERE name = 'High - 4 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    'Password Reset',
    'User cannot log in, forgot password, or password expired.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'Password Reset');

INSERT INTO ost_help_topic
    (ispublic, noautoresp, topic_pid, sla_id, dept_id, topic, notes, created, updated)
SELECT
    1, 0,
    (SELECT topic_id FROM ost_help_topic WHERE topic = 'Account Issues' LIMIT 1),
    (SELECT id FROM ost_sla WHERE name = 'High - 4 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    'Account Lockout',
    'Account locked after multiple failed login attempts.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'Account Lockout');

INSERT INTO ost_help_topic
    (ispublic, noautoresp, topic_pid, sla_id, dept_id, topic, notes, created, updated)
SELECT
    1, 0,
    (SELECT topic_id FROM ost_help_topic WHERE topic = 'Account Issues' LIMIT 1),
    (SELECT id FROM ost_sla WHERE name = 'Normal - 8 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    'New User Setup',
    'Onboarding a new employee — account creation, equipment, access.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'New User Setup');

INSERT INTO ost_help_topic
    (ispublic, noautoresp, topic_pid, sla_id, dept_id, topic, notes, created, updated)
SELECT
    1, 0,
    (SELECT topic_id FROM ost_help_topic WHERE topic = 'Account Issues' LIMIT 1),
    (SELECT id FROM ost_sla WHERE name = 'Normal - 8 Hours' LIMIT 1),
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    'Access Request',
    'Request for access to a system, share, or application.',
    NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_help_topic WHERE topic = 'Access Request');

-- Verify
SELECT 'SLA' AS section, name AS item FROM ost_sla
UNION ALL SELECT 'Department', name FROM ost_department
UNION ALL SELECT 'Help Topic', topic FROM ost_help_topic
ORDER BY section, item;
