-- ============================================================
-- osTicket Seed: Staff / Agent Accounts
-- Maps to our AD users in corp.local
-- Passwords are hashed — agents should use "Forgot Password"
-- on first login, or set via Admin Panel > Staff.
-- ============================================================

USE osticket;

-- ── Roles ─────────────────────────────────────────────────────
-- role_id references ost_role. Default roles created by installer:
--   1 = All Access (admin)
--   2 = Expanded Access
--   3 = Limited Access
--   4 = Read Only

-- ── Staff: jsmith — IT Admin / Manager ────────────────────────
INSERT INTO ost_staff
    (dept_id, role_id, username, firstname, lastname, email,
     phone, phone_ext, dept_access, isadmin, isactive,
     isvisible, onvacation, assigned_only, show_assigned_tickets,
     max_page_size, passwd, created, lastlogin, passwdreset, updated)
SELECT
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    1,          -- All Access
    'jsmith',
    'James', 'Smith',
    'jsmith@corp.local',
    '555-0101', '',
    0,          -- dept_access (0 = all depts)
    1,          -- isadmin
    1,          -- isactive
    1,          -- isvisible
    0,          -- onvacation
    0,          -- assigned_only
    0,          -- show_assigned_tickets
    25,
    MD5('Helpd3sk!Admin'),  -- placeholder; reset via UI
    NOW(), NOW(), NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_staff WHERE username = 'jsmith');

-- ── Staff: alopez — L1 Help Desk Technician ───────────────────
INSERT INTO ost_staff
    (dept_id, role_id, username, firstname, lastname, email,
     phone, phone_ext, dept_access, isadmin, isactive,
     isvisible, onvacation, assigned_only, show_assigned_tickets,
     max_page_size, passwd, created, lastlogin, passwdreset, updated)
SELECT
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    2,          -- Expanded Access
    'alopez',
    'Ana', 'Lopez',
    'alopez@corp.local',
    '555-0102', '',
    0,
    0,          -- not admin
    1, 1, 0, 0, 0,
    25,
    MD5('Helpd3sk!Pass'),
    NOW(), NOW(), NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_staff WHERE username = 'alopez');

-- ── Staff: tnguyen — L1 Help Desk Technician ──────────────────
INSERT INTO ost_staff
    (dept_id, role_id, username, firstname, lastname, email,
     phone, phone_ext, dept_access, isadmin, isactive,
     isvisible, onvacation, assigned_only, show_assigned_tickets,
     max_page_size, passwd, created, lastlogin, passwdreset, updated)
SELECT
    (SELECT id FROM ost_department WHERE name = 'IT Helpdesk' LIMIT 1),
    2,
    'tnguyen',
    'Tommy', 'Nguyen',
    'tnguyen@corp.local',
    '555-0104', '',
    0,
    0,
    1, 1, 0, 0, 0,
    25,
    MD5('Helpd3sk!Pass'),
    NOW(), NOW(), NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_staff WHERE username = 'tnguyen');

-- ── Staff: mchen — Network Engineer / Net Ops ─────────────────
INSERT INTO ost_staff
    (dept_id, role_id, username, firstname, lastname, email,
     phone, phone_ext, dept_access, isadmin, isactive,
     isvisible, onvacation, assigned_only, show_assigned_tickets,
     max_page_size, passwd, created, lastlogin, passwdreset, updated)
SELECT
    (SELECT id FROM ost_department WHERE name = 'Network Operations' LIMIT 1),
    2,
    'mchen',
    'Michael', 'Chen',
    'mchen@corp.local',
    '555-0103', '',
    0,
    0,
    1, 1, 0, 0, 0,
    25,
    MD5('Helpd3sk!Pass'),
    NOW(), NOW(), NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM ost_staff WHERE username = 'mchen');

-- ── End Users (ticket requesters from corp.local) ─────────────
-- ost_user + ost_user_email must both be populated.

-- Helper procedure to insert a user+email atomically
DROP PROCEDURE IF EXISTS upsert_user;
DELIMITER //
CREATE PROCEDURE upsert_user(
    IN p_name    VARCHAR(128),
    IN p_email   VARCHAR(128)
)
BEGIN
    DECLARE v_user_id INT;
    -- Insert user if not exists
    IF NOT EXISTS (SELECT 1 FROM ost_user_email WHERE address = p_email) THEN
        INSERT INTO ost_user (org_id, default_email_id, status, name, created, updated)
        VALUES (0, 0, 0, p_name, NOW(), NOW());
        SET v_user_id = LAST_INSERT_ID();
        INSERT INTO ost_user_email (user_id, flags, address)
        VALUES (v_user_id, 0, p_email);
        UPDATE ost_user SET default_email_id = LAST_INSERT_ID() WHERE id = v_user_id;
    END IF;
END //
DELIMITER ;

CALL upsert_user('David Johnson',   'djohnson@corp.local');
CALL upsert_user('Karen Thompson',  'kthompson@corp.local');
CALL upsert_user('Sarah Williams',  'swilliams@corp.local');
CALL upsert_user('Brian Washington','bwashington@corp.local');
CALL upsert_user('Laura Martinez',  'lmartinez@corp.local');
CALL upsert_user('Raj Patel',       'rpatel@corp.local');

DROP PROCEDURE IF EXISTS upsert_user;

-- Verify
SELECT 'Staff' AS type, CONCAT(firstname, ' ', lastname) AS name, email, IF(isadmin,'Admin','Agent') AS role
FROM ost_staff
UNION ALL
SELECT 'End User', name, (SELECT address FROM ost_user_email WHERE user_id = u.id LIMIT 1), 'Requester'
FROM ost_user u
ORDER BY type, name;
