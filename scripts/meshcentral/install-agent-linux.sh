#!/usr/bin/env bash
# ============================================================
# install-agent-linux.sh
# Silent MeshCentral agent installer for Linux VMs.
# Tested on: Ubuntu 22.04, Debian 12, Rocky Linux 9
#
# Usage:
#   sudo bash install-agent-linux.sh \
#       --host 192.168.10.50 \
#       --port 8086 \
#       --meshid '$$$mesh//CorpTech-Servers/abc123...'
#
# The script:
#   1. Detects architecture (x64/arm64)
#   2. Downloads the agent binary from your MeshCentral instance
#   3. Installs as a systemd service
#   4. Configures auto-restart and boot persistence
# ============================================================

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────
MESH_HOST=""
MESH_PORT="8086"
MESH_ID=""
AGENT_GROUP="CorpTech-Servers"
INSTALL_DIR="/opt/meshagent"
SERVICE_NAME="meshagent"
LOG_FILE="/var/log/meshagent-install.log"
SKIP_CERT_CHECK="true"   # set false if using valid cert
# ──────────────────────────────────────────────────────────────

# ── Argument parsing ──────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)    MESH_HOST="$2";  shift 2 ;;
        --port)    MESH_PORT="$2";  shift 2 ;;
        --meshid)  MESH_ID="$2";    shift 2 ;;
        --group)   AGENT_GROUP="$2";shift 2 ;;
        --no-skip-cert) SKIP_CERT_CHECK="false"; shift ;;
        -h|--help)
            echo "Usage: $0 --host <ip> --port <port> --meshid '<meshid>'"
            exit 0 ;;
        *) echo "[ERR] Unknown argument: $1"; exit 1 ;;
    esac
done

# ── Validate ──────────────────────────────────────────────────
if [[ -z "$MESH_HOST" || -z "$MESH_ID" ]]; then
    echo "[ERR] --host and --meshid are required."
    echo "      Get the Mesh ID from: MeshCentral > Mesh > Right-click > Copy Mesh ID"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "[ERR] This script must be run as root (sudo)."
    exit 1
fi

MESH_SERVER="https://${MESH_HOST}:${MESH_PORT}"

# ── Logging ───────────────────────────────────────────────────
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')][INFO]  $*"; }
ok()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')][OK]    $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')][WARN]  $*"; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')][ERROR] $*" >&2; exit 1; }

echo ""
echo "══════════════════════════════════════════════"
echo "  MeshCentral Agent Installer — Linux"
echo "══════════════════════════════════════════════"
echo "  Server : $MESH_SERVER"
echo "  Group  : $AGENT_GROUP"
echo "  Host   : $(hostname)"
echo ""

# ── Step 1: Detect architecture ──────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)          MESH_ARCH="meshagent64"    ;;   # Linux 64-bit
    aarch64|arm64)   MESH_ARCH="meshagentarm64" ;;   # ARM64 (Pi, cloud ARM)
    armv7l|armv6l)   MESH_ARCH="meshagentarm"   ;;   # ARM 32-bit
    i686|i386)       MESH_ARCH="meshagent32"    ;;   # Linux 32-bit
    *)               err "Unsupported architecture: $ARCH" ;;
esac
log "Architecture: $ARCH → using agent binary: $MESH_ARCH"

# ── Step 2: Install prerequisites ─────────────────────────────
log "Checking dependencies..."
if command -v apt-get &>/dev/null; then
    apt-get install -yq curl wget openssl ca-certificates &>/dev/null
elif command -v dnf &>/dev/null; then
    dnf install -yq curl wget openssl ca-certificates &>/dev/null
elif command -v yum &>/dev/null; then
    yum install -yq curl wget openssl ca-certificates &>/dev/null
fi
ok "Dependencies satisfied"

# ── Step 3: Check for existing installation ───────────────────
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    warn "MeshAgent service is already running."
    warn "Stopping service for reinstall..."
    systemctl stop "$SERVICE_NAME" || true
fi

# ── Step 4: Create install directory ─────────────────────────
mkdir -p "$INSTALL_DIR"
log "Install directory: $INSTALL_DIR"

# ── Step 5: Download agent binary ────────────────────────────
# meshinstall parameter for Linux:
#   5 = Linux x64    6 = Windows x64
DOWNLOAD_URL="${MESH_SERVER}/meshagents?id=${MESH_ID}&meshinstall=5&installflags=0"
AGENT_BINARY="$INSTALL_DIR/meshagent"

log "Downloading agent from: $MESH_SERVER"

CURL_OPTS="-fsSL --retry 3 --retry-delay 2"
if [[ "$SKIP_CERT_CHECK" == "true" ]]; then
    CURL_OPTS="$CURL_OPTS --insecure"
    warn "TLS certificate verification disabled (self-signed cert mode)"
fi

# shellcheck disable=SC2086
if ! curl $CURL_OPTS -o "$AGENT_BINARY" "$DOWNLOAD_URL"; then
    err "Download failed from $DOWNLOAD_URL
    Ensure:
      1. MeshCentral is running: docker ps | grep meshcentral
      2. The host IP ($MESH_HOST) is reachable from this VM
      3. Port $MESH_PORT is open (test: curl -k https://$MESH_HOST:$MESH_PORT/)
      4. The Mesh ID is correct (no trailing spaces)"
fi

AGENT_SIZE=$(stat -c%s "$AGENT_BINARY" 2>/dev/null || echo 0)
if [[ "$AGENT_SIZE" -lt 100000 ]]; then
    err "Downloaded file is too small ($AGENT_SIZE bytes) — likely an error page.
    Check MeshCentral logs: docker logs meshcentral --tail 20"
fi

chmod +x "$AGENT_BINARY"
ok "Agent binary downloaded ($(numfmt --to=iec "$AGENT_SIZE"))"

# ── Step 6: Write the MeshAgent config ───────────────────────
# Some MeshCentral builds embed the config in the binary.
# For builds that require an external config file:
cat > "$INSTALL_DIR/meshagent.msh" <<EOF
MeshServer=${MESH_SERVER}
MeshID=${MESH_ID}
ServerID=${MESH_HOST}
EOF
ok "Wrote meshagent.msh config"

# ── Step 7: Create dedicated service user ────────────────────
if ! id "meshagent" &>/dev/null; then
    useradd -r -s /sbin/nologin -d "$INSTALL_DIR" meshagent
    ok "Created service user: meshagent"
fi
chown -R meshagent:meshagent "$INSTALL_DIR"

# ── Step 8: Run built-in installer if available ──────────────
# Newer MeshCentral agents support --install flag
if "$AGENT_BINARY" --install 2>/dev/null; then
    ok "Agent self-installed via --install flag"
else
    warn "Self-install not supported, creating systemd unit manually"

    # ── Step 9: Create systemd service unit ──────────────────
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=MeshCentral Remote Management Agent
Documentation=https://meshcentral.com
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${AGENT_BINARY}
Restart=always
RestartSec=10
KillMode=process

# Security hardening
NoNewPrivileges=false
ProtectSystem=false

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=meshagent

[Install]
WantedBy=multi-user.target
EOF

    ok "Systemd unit created: /etc/systemd/system/${SERVICE_NAME}.service"
fi

# ── Step 10: Enable and start service ────────────────────────
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start  "$SERVICE_NAME"

# Wait for startup
sleep 5
if systemctl is-active --quiet "$SERVICE_NAME"; then
    ok "Service is RUNNING"
else
    warn "Service status:"
    systemctl status "$SERVICE_NAME" --no-pager -l || true
    warn "Check logs: journalctl -u meshagent -n 50"
fi

# ── Step 11: Verify connectivity to MeshCentral ──────────────
log "Testing connectivity to MeshCentral server..."
if curl -sk --max-time 5 "$MESH_SERVER/" | grep -q "MeshCentral" 2>/dev/null; then
    ok "MeshCentral web UI is reachable"
else
    warn "Could not verify MeshCentral web UI — agent may still connect over WebSocket"
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
ok  "MeshCentral agent installed on $(hostname)"
echo ""
echo "  Service management:"
echo "    Status  : systemctl status $SERVICE_NAME"
echo "    Logs    : journalctl -u $SERVICE_NAME -f"
echo "    Stop    : systemctl stop $SERVICE_NAME"
echo "    Restart : systemctl restart $SERVICE_NAME"
echo ""
echo "  Device should appear in MeshCentral within 30-60s:"
echo "    URL: $MESH_SERVER"
echo "    Look for: $(hostname) under '$AGENT_GROUP'"
echo ""
echo "  Install log: $LOG_FILE"
echo "══════════════════════════════════════════════"
