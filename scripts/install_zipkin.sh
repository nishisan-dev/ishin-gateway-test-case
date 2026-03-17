#!/usr/bin/env bash
###############################################################################
# install_zipkin.sh — Provisiona Zipkin Server standalone via JAR
#
# Instala OpenJDK 21 JRE e configura Zipkin como serviço systemd.
###############################################################################
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

NODE_NAME="${1:?missing node name}"
ZIPKIN_VERSION="3.5.2"
ZIPKIN_JAR_URL="https://search.maven.org/remote_content?g=io.zipkin&a=zipkin-server&v=${ZIPKIN_VERSION}&c=exec"
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

# ─── Download do JAR ────────────────────────────────────────────────────────
if [[ ! -f "${ZIPKIN_JAR}" ]]; then
  echo "Baixando Zipkin Server v${ZIPKIN_VERSION}..."
  curl -fSL "${ZIPKIN_JAR_URL}" -o "${ZIPKIN_JAR}"
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

sleep 3
systemctl --no-pager --full status zipkin
