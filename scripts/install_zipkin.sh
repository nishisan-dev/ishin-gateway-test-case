#!/usr/bin/env bash
###############################################################################
# install_zipkin.sh — Provisiona Zipkin Server standalone via JAR
#
# Instala OpenJDK 21 JRE e configura Zipkin como serviço systemd.
###############################################################################
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

NODE_NAME="${1:?missing node name}"
ZIPKIN_DIR="/opt/zipkin"
ZIPKIN_JAR="${ZIPKIN_DIR}/zipkin.jar"
ZIPKIN_USER="zipkin"

# ─── Java ────────────────────────────────────────────────────────────────────
apt-get install -y openjdk-21-jre-headless

# ─── Usuário e diretórios ────────────────────────────────────────────────────
if ! id -u "${ZIPKIN_USER}" &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "${ZIPKIN_USER}"
fi

mkdir -p "${ZIPKIN_DIR}"

# ─── Download do JAR via quickstart oficial ─────────────────────────────────
if [[ ! -f "${ZIPKIN_JAR}" ]]; then
  echo "Baixando Zipkin Server via quickstart oficial..."
  cd "${ZIPKIN_DIR}"
  curl -sSL https://zipkin.io/quickstart.sh | bash -s
fi

chown -R "${ZIPKIN_USER}:${ZIPKIN_USER}" "${ZIPKIN_DIR}"

# ─── Systemd unit ───────────────────────────────────────────────────────────
cat <<EOF >/etc/systemd/system/zipkin.service
[Unit]
Description=Zipkin Server
After=network.target

[Service]
Type=simple
User=${ZIPKIN_USER}
Group=${ZIPKIN_USER}
ExecStart=/usr/bin/java -Xms128m -Xmx512m -jar ${ZIPKIN_JAR}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=zipkin

# Storage in-memory (default do Zipkin)
Environment=STORAGE_TYPE=mem

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zipkin
systemctl restart zipkin

# Aguarda startup do Java (pode demorar ~10s)
echo "Aguardando Zipkin iniciar..."
sleep 10
systemctl --no-pager --full status zipkin || true
