#!/usr/bin/env bash
# ============================================================
# run-seed.sh — Execute all osTicket seed SQL files against
#               the MariaDB container.
#
# Usage:
#   bash run-seed.sh               Run all seed files in order
#   bash run-seed.sh --verify      Run verification queries only
#   bash run-seed.sh --reset       Drop and re-seed (destructive!)
#
# Prerequisites:
#   - Docker Compose stack must be running (start-lab.sh up)
#   - Run from the IT_Simulation/docker/ directory
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(dirname "$SCRIPT_DIR")/.env"

# Load env vars
if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi

DB_CONTAINER="${DB_CONTAINER:-osticket_db}"
DB_NAME="${DB_NAME:-osticket}"
DB_USER="${DB_USER:-osticket}"
DB_PASS="${OST_DB_PASSWORD:-0sTick3t!P@ssChangeMeNow}"
DB_ROOT_PASS="${OST_DB_ROOT_PASSWORD:-R00tP@ssw0rd!ChangeMeNow}"

SEED_DIR="$SCRIPT_DIR"
SEED_FILES=(
    "00-departments-sla-topics.sql"
    "01-staff-agents.sql"
    "02-tickets.sql"
)

log()  { echo -e "\033[0;36m[*]\033[0m $*"; }
ok()   { echo -e "\033[0;32m[+]\033[0m $*"; }
warn() { echo -e "\033[0;33m[!]\033[0m $*"; }
err()  { echo -e "\033[0;31m[ERR]\033[0m $*" >&2; }

# ── Wait for DB to be ready ───────────────────────────────────
wait_for_db() {
    log "Waiting for MariaDB container to be ready..."
    local retries=30
    while ! docker exec "$DB_CONTAINER" \
            mysqladmin ping -u root -p"$DB_ROOT_PASS" --silent 2>/dev/null; do
        retries=$((retries - 1))
        if [[ $retries -le 0 ]]; then
            err "MariaDB did not become ready in time."
            err "Is the container running? Check: docker ps"
            exit 1
        fi
        sleep 2
    done
    ok "Database is ready."
}

# ── Run a SQL file ────────────────────────────────────────────
run_sql_file() {
    local file="$1"
    local filepath="$SEED_DIR/$file"

    if [[ ! -f "$filepath" ]]; then
        err "SQL file not found: $filepath"
        return 1
    fi

    log "Running: $file"
    docker exec -i "$DB_CONTAINER" \
        mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
        < "$filepath" 2>&1 | grep -v "^Warning:"

    ok "Completed: $file"
}

# ── Verify: print ticket summary ─────────────────────────────
run_verify() {
    log "Ticket summary:"
    docker exec -i "$DB_CONTAINER" \
        mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
        --table 2>/dev/null <<'SQL'
SELECT
    t.number         AS `#`,
    SUBSTRING(t.subject, 1, 45) AS `Subject`,
    u.name           AS `Requester`,
    CONCAT(s.firstname,' ',s.lastname) AS `Agent`,
    ts.name          AS `Status`
FROM ost_ticket t
JOIN ost_user          u  ON u.id       = t.user_id
JOIN ost_ticket_status ts ON ts.id      = t.status_id
LEFT JOIN ost_staff    s  ON s.staff_id = t.staff_id
ORDER BY t.number;
SQL
}

# ── Reset: remove all seeded data ────────────────────────────
run_reset() {
    warn "This will DELETE all tickets, staff, users, departments, SLA plans, and help topics."
    read -rp "Type 'RESET' to confirm: " confirm
    if [[ "$confirm" != "RESET" ]]; then
        echo "Aborted."; exit 0
    fi

    log "Resetting seed data..."
    docker exec -i "$DB_CONTAINER" \
        mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" <<'SQL'
SET FOREIGN_KEY_CHECKS=0;
DELETE FROM ost_thread_entry WHERE 1;
DELETE FROM ost_thread WHERE object_type = 'T';
DELETE FROM ost_ticket WHERE number BETWEEN '100001' AND '100015';
DELETE FROM ost_user_email WHERE address LIKE '%@corp.local' AND address NOT LIKE 'admin%';
DELETE FROM ost_user WHERE name IN (
    'David Johnson','Karen Thompson','Sarah Williams',
    'Brian Washington','Laura Martinez','Raj Patel'
);
DELETE FROM ost_staff WHERE username IN ('jsmith','alopez','tnguyen','mchen');
DELETE FROM ost_help_topic WHERE topic IN (
    'Account Issues','Hardware','Software','Network',
    'Password Reset','Account Lockout','New User Setup','Access Request'
);
DELETE FROM ost_department WHERE name IN ('IT Helpdesk','Network Operations');
DELETE FROM ost_sla WHERE name IN (
    'Critical - 1 Hour','High - 4 Hours','Normal - 8 Hours','Low - 24 Hours'
);
SET FOREIGN_KEY_CHECKS=1;
SQL
    ok "Seed data removed. Run without --reset to re-seed."
}

# ── Main ──────────────────────────────────────────────────────
case "${1:-}" in
    --verify)
        wait_for_db
        run_verify
        ;;
    --reset)
        wait_for_db
        run_reset
        ;;
    "")
        # Check osTicket installer has run (ost_ticket_status must exist)
        log "Checking that osTicket web installer has completed..."
        STATUS_COUNT=$(docker exec -i "$DB_CONTAINER" \
            mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -sNe \
            "SELECT COUNT(*) FROM information_schema.tables \
             WHERE table_schema='$DB_NAME' AND table_name='ost_ticket_status';" 2>/dev/null || echo 0)

        if [[ "$STATUS_COUNT" -eq 0 ]]; then
            err "osTicket tables not found. Complete the web installer first:"
            err "  1. Open http://\${HOST_IP}:8080/setup"
            err "  2. Run through the installation wizard"
            err "  3. Delete or rename the /setup directory when done"
            err "  4. Re-run this script"
            exit 1
        fi

        wait_for_db
        log "Starting seed sequence..."
        echo ""

        for f in "${SEED_FILES[@]}"; do
            run_sql_file "$f"
            echo ""
        done

        echo ""
        ok "All seed files applied successfully."
        echo ""
        run_verify
        echo ""
        log "osTicket is ready at: http://\${HOST_IP:-localhost}:8080"
        log "Admin panel:          http://\${HOST_IP:-localhost}:8080/scp"
        log "Default admin:        admin@corp.local"
        ;;
    *)
        echo "Usage: $0 [--verify | --reset]"
        exit 1
        ;;
esac
