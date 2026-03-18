#!/usr/bin/env bash
###############################################################################
# start.sh — Sobe todo o laboratório ishin-gateway na ordem correta
#
# Uso:
#   ./start.sh              # sobe tudo
#   ./start.sh web-1        # sobe apenas VMs específicas
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Cores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SEPARATOR="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─── Ordem de boot ───────────────────────────────────────────────────────────
ALL_VMS=("web-1" "zipkin-1" "tunnel-1" "ishin-1" "ishin-2")

if [[ $# -gt 0 ]]; then
  TARGET_VMS=("$@")
else
  TARGET_VMS=("${ALL_VMS[@]}")
fi

# ─── Boot ────────────────────────────────────────────────────────────────────
FAILED=()
SUCCEEDED=()

for vm in "${TARGET_VMS[@]}"; do
  echo -e "\n${CYAN}${BOLD}▶ Subindo ${vm}...${NC}\n"
  if vagrant up "$vm"; then
    SUCCEEDED+=("$vm")
  else
    echo -e "${RED}✗ Falha ao subir ${vm}${NC}"
    FAILED+=("$vm")
  fi
done

# ─── Banner final ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${SEPARATOR}${NC}"
echo -e "${BOLD}  🚀 ishin-gateway Lab — Resumo do Ambiente${NC}"
echo -e "${BOLD}${SEPARATOR}${NC}"
echo ""

# Status geral
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✅ Todas as VMs subiram com sucesso!${NC}"
else
  echo -e "  ${YELLOW}⚠️  ${#SUCCEEDED[@]}/${#TARGET_VMS[@]} VMs OK — ${RED}${#FAILED[@]} com falha: ${FAILED[*]}${NC}"
fi

echo ""
echo -e "${BOLD}${SEPARATOR}${NC}"
echo -e "${BOLD}  📋 Endpoints disponíveis${NC}"
echo -e "${BOLD}${SEPARATOR}${NC}"

# Função helper para checar se VM está na lista de sucesso
vm_ok() { for v in "${SUCCEEDED[@]}"; do [[ "$v" == "$1" ]] && return 0; done; return 1; }

echo ""

if vm_ok "web-1"; then
  echo -e "  ${GREEN}●${NC} ${BOLD}web-1${NC} ${DIM}(192.168.56.21)${NC}"
  echo -e "    🌐 Nginx:      ${CYAN}http://localhost:18080${NC}"
  echo ""
fi

if vm_ok "zipkin-1"; then
  echo -e "  ${GREEN}●${NC} ${BOLD}zipkin-1${NC} ${DIM}(192.168.56.31)${NC}"
  echo -e "    🔍 Zipkin UI:  ${CYAN}http://localhost:39411${NC}"
  echo -e "    📡 API:        ${CYAN}http://localhost:39411/api/v2/traces${NC}"
  echo ""
fi

if vm_ok "tunnel-1"; then
  echo -e "  ${GREEN}●${NC} ${BOLD}tunnel-1${NC} ${DIM}(192.168.56.10)${NC}  ${YELLOW}[TUNNEL L4 LB]${NC}"
  echo -e "    🔀 Tunnel:     ${CYAN}http://localhost:9090${NC}  ${DIM}(vPort → proxies)${NC}"
  echo -e "    ⚙️  Management: ${CYAN}http://localhost:9190${NC}"
  echo -e "    📊 Dashboard:  ${CYAN}http://localhost:9200${NC}"
  echo -e "    🔗 Cluster:    ${DIM}192.168.56.10:7100${NC}"
  echo ""
fi

if vm_ok "ishin-1"; then
  echo -e "  ${GREEN}●${NC} ${BOLD}ishin-1${NC} ${DIM}(192.168.56.11)${NC}"
  echo -e "    🔀 Proxy:      ${CYAN}http://localhost:19090${NC}"
  echo -e "    ⚙️  Management: ${CYAN}http://localhost:19190${NC}"
  echo -e "    📊 Dashboard:  ${CYAN}http://localhost:19200${NC}"
  echo -e "    🔗 Cluster:    ${DIM}192.168.56.11:7100${NC}"
  echo ""
fi

if vm_ok "ishin-2"; then
  echo -e "  ${GREEN}●${NC} ${BOLD}ishin-2${NC} ${DIM}(192.168.56.12)${NC}"
  echo -e "    🔀 Proxy:      ${CYAN}http://localhost:29090${NC}"
  echo -e "    ⚙️  Management: ${CYAN}http://localhost:29190${NC}"
  echo -e "    📊 Dashboard:  ${CYAN}http://localhost:29200${NC}"
  echo -e "    🔗 Cluster:    ${DIM}192.168.56.12:7100${NC}"
  echo ""
fi

echo -e "${BOLD}${SEPARATOR}${NC}"
echo -e "  ${DIM}Teste rápido (via tunnel):  curl http://localhost:9090${NC}"
echo -e "  ${DIM}Teste direto (proxy ishin-1): curl http://localhost:19090${NC}"
echo -e "${BOLD}${SEPARATOR}${NC}"
echo ""
