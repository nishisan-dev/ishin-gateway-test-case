#!/usr/bin/env bash
###############################################################################
# start.sh — Sobe o laboratório ishin-gateway via Docker Compose
#
# Uso:
#   ./start.sh              # sobe tudo
#   ./start.sh --detach     # sobe em background (default)
#   ./start.sh --follow     # sobe e segue os logs
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"

# ─── Cores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SEPARATOR="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

FOLLOW=false
if [[ "${1:-}" == "--follow" ]]; then
  FOLLOW=true
fi

# ─── Subir containers ───────────────────────────────────────────────────────
echo -e "${CYAN}${BOLD}▶ Subindo o ambiente Docker Compose...${NC}\n"
docker compose up -d --wait

# ─── Aguardar health checks ─────────────────────────────────────────────────
echo -e "\n${CYAN}${BOLD}▶ Verificando saúde dos containers...${NC}\n"

SERVICES=("web-1" "zipkin-1" "tunnel-1" "ishin-1" "ishin-2")
FAILED=()
SUCCEEDED=()

for svc in "${SERVICES[@]}"; do
  STATUS=$(docker compose ps --format '{{.Health}}' "$svc" 2>/dev/null || echo "unknown")
  if [[ "$STATUS" == "healthy" ]]; then
    echo -e "  ${GREEN}✔${NC} ${svc}: ${GREEN}healthy${NC}"
    SUCCEEDED+=("$svc")
  else
    echo -e "  ${RED}✗${NC} ${svc}: ${RED}${STATUS}${NC}"
    FAILED+=("$svc")
  fi
done

# ─── Banner final ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${SEPARATOR}${NC}"
echo -e "${BOLD}  🚀 ishin-gateway Lab (Docker) — Resumo do Ambiente${NC}"
echo -e "${BOLD}${SEPARATOR}${NC}"
echo ""

if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✅ Todos os containers estão healthy!${NC}"
else
  echo -e "  ${YELLOW}⚠️  ${#SUCCEEDED[@]}/${#SERVICES[@]} healthy — ${RED}${#FAILED[@]} com problema: ${FAILED[*]}${NC}"
fi

echo ""
echo -e "${BOLD}${SEPARATOR}${NC}"
echo -e "${BOLD}  📋 Endpoints disponíveis${NC}"
echo -e "${BOLD}${SEPARATOR}${NC}"
echo ""

echo -e "  ${GREEN}●${NC} ${BOLD}web-1${NC}"
echo -e "    🌐 Nginx:       ${CYAN}http://localhost:18080${NC}"
echo ""

echo -e "  ${GREEN}●${NC} ${BOLD}zipkin-1${NC}"
echo -e "    🔍 Zipkin UI:   ${CYAN}http://localhost:39411${NC}"
echo -e "    📡 API:         ${CYAN}http://localhost:39411/api/v2/traces${NC}"
echo ""

echo -e "  ${GREEN}●${NC} ${BOLD}tunnel-1${NC}  ${YELLOW}[TUNNEL L4 LB]${NC}"
echo -e "    🔀 Tunnel:      ${CYAN}http://localhost:9090${NC}  ${DIM}(vPort → proxies)${NC}"
echo -e "    ⚙️  Management:  ${CYAN}http://localhost:9190${NC}"
echo -e "    📊 Dashboard:   ${CYAN}http://localhost:9200${NC}"
echo ""

echo -e "  ${GREEN}●${NC} ${BOLD}ishin-1${NC}"
echo -e "    🔀 Proxy:       ${CYAN}http://localhost:19090${NC}"
echo -e "    ⚙️  Management:  ${CYAN}http://localhost:19190${NC}"
echo -e "    📊 Dashboard:   ${CYAN}http://localhost:19200${NC}"
echo ""

echo -e "  ${GREEN}●${NC} ${BOLD}ishin-2${NC}"
echo -e "    🔀 Proxy:       ${CYAN}http://localhost:29090${NC}"
echo -e "    ⚙️  Management:  ${CYAN}http://localhost:29190${NC}"
echo -e "    📊 Dashboard:   ${CYAN}http://localhost:29200${NC}"
echo ""

echo -e "${BOLD}${SEPARATOR}${NC}"
echo -e "  ${DIM}Teste rápido (via tunnel):    curl http://localhost:9090${NC}"
echo -e "  ${DIM}Teste direto (proxy ishin-1): curl http://localhost:19090${NC}"
echo -e "${BOLD}${SEPARATOR}${NC}"
echo ""

# ─── Seguir logs se pedido ──────────────────────────────────────────────────
if [[ "$FOLLOW" == "true" ]]; then
  echo -e "${CYAN}${BOLD}▶ Seguindo logs... (Ctrl+C para sair)${NC}\n"
  docker compose logs -f
fi
