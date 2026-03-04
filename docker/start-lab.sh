#!/usr/bin/env bash
# ============================================================
# start-lab.sh — Bring up the full CorpTech IT Simulation Lab
# Usage: bash start-lab.sh [up|down|logs|status]
# ============================================================

set -euo pipefail

COMPOSE_FILE="$(dirname "$0")/docker-compose.yml"
ENV_FILE="$(dirname "$0")/.env"

check_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "[ERROR] .env file not found at $ENV_FILE"
        echo "  Copy .env.example to .env and fill in your values."
        exit 1
    fi
}

cmd="${1:-up}"

case "$cmd" in
    up)
        check_env
        echo "[*] Starting CorpTech IT Simulation Lab..."
        docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
        echo ""
        echo "  osTicket   -> http://$(grep HOST_IP "$ENV_FILE" | cut -d= -f2):8080"
        echo "  MeshCentral-> https://$(grep MESH_HOSTNAME "$ENV_FILE" | cut -d= -f2):8086"
        echo ""
        echo "[*] Run 'bash start-lab.sh logs' to follow container output."
        ;;
    down)
        echo "[*] Stopping all lab services..."
        docker compose -f "$COMPOSE_FILE" down
        ;;
    logs)
        docker compose -f "$COMPOSE_FILE" logs -f --tail=50
        ;;
    status)
        docker compose -f "$COMPOSE_FILE" ps
        ;;
    reset)
        echo "[!] WARNING: This will destroy ALL volumes (osTicket DB, MeshCentral data)."
        read -rp "Type 'yes' to confirm: " confirm
        if [[ "$confirm" == "yes" ]]; then
            docker compose -f "$COMPOSE_FILE" down -v
            echo "[*] Volumes removed. Run './start-lab.sh up' to start fresh."
        else
            echo "Aborted."
        fi
        ;;
    *)
        echo "Usage: $0 [up|down|logs|status|reset]"
        exit 1
        ;;
esac
