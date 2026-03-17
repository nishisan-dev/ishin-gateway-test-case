#!/usr/bin/env bash
###############################################################################
# install_zipkin.sh — Provisiona Elasticsearch + Zipkin Server
#
# Instala Elasticsearch (single-node, recursos limitados) e Zipkin com
# storage persistente via ES. Ambos rodam na mesma VM.
###############################################################################
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

NODE_NAME="${1:?missing node name}"
ZIPKIN_DIR="/opt/zipkin"
ZIPKIN_JAR="${ZIPKIN_DIR}/zipkin.jar"
ZIPKIN_USER="zipkin"
ES_HEAP="512m"
ES_VERSION="8.17.0"

# ─── Java ────────────────────────────────────────────────────────────────────
apt-get install -y openjdk-21-jre-headless

# ─── Elasticsearch ──────────────────────────────────────────────────────────

# Instalar ES se não estiver presente
if ! dpkg-query -W -f='${Status}' elasticsearch 2>/dev/null | grep -q "install ok installed"; then
  echo "Instalando Elasticsearch ${ES_VERSION}..."

  # Importar GPG key e adicionar repositório
  curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
    gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

  echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" \
    > /etc/apt/sources.list.d/elastic-8.x.list

  apt-get update
  apt-get install -y elasticsearch
fi

# Configuração do Elasticsearch — single-node, sem segurança, recursos limitados
cat <<EOF >/etc/elasticsearch/elasticsearch.yml
# ─── Cluster ─────────────────────────────────────────────────────────────────
cluster.name: zipkin-storage
node.name: ${NODE_NAME}
discovery.type: single-node

# ─── Rede ────────────────────────────────────────────────────────────────────
network.host: 127.0.0.1
http.port: 9200

# ─── Segurança (desabilitada para lab) ───────────────────────────────────────
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false

# ─── Desabilitar features pesadas ────────────────────────────────────────────
xpack.ml.enabled: false
xpack.watcher.enabled: false
xpack.monitoring.collection.enabled: false

# ─── Paths ───────────────────────────────────────────────────────────────────
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch

# ─── Indices (contenção de disco) ────────────────────────────────────────────
action.auto_create_index: true
EOF

# JVM Heap — limitar para não explodir a VM
cat <<EOF >/etc/elasticsearch/jvm.options.d/heap.options
-Xms${ES_HEAP}
-Xmx${ES_HEAP}
EOF

systemctl daemon-reload
systemctl enable elasticsearch
systemctl restart elasticsearch

# Aguarda ES ficar healthy
echo "Aguardando Elasticsearch..."
for i in $(seq 1 30); do
  if curl -s http://127.0.0.1:9200/_cluster/health?timeout=2s | grep -q '"status"'; then
    echo "Elasticsearch está UP."
    break
  fi
  sleep 2
done

# ─── ILM: auto-delete de índices antigos (3 dias) ──────────────────────────
# Cria policy de lifecycle para limpar traces antigos automaticamente
curl -s -X PUT "http://127.0.0.1:9200/_ilm/policy/zipkin-retention" \
  -H 'Content-Type: application/json' -d '{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_age": "1d",
            "max_primary_shard_size": "1gb"
          }
        }
      },
      "delete": {
        "min_age": "3d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}' || true

echo ""

# ─── Zipkin ─────────────────────────────────────────────────────────────────

# Usuário e diretórios
if ! id -u "${ZIPKIN_USER}" &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "${ZIPKIN_USER}"
fi

mkdir -p "${ZIPKIN_DIR}"

# Download do JAR via quickstart oficial
if [[ ! -f "${ZIPKIN_JAR}" ]]; then
  echo "Baixando Zipkin Server via quickstart oficial..."
  cd "${ZIPKIN_DIR}"
  curl -sSL https://zipkin.io/quickstart.sh | bash -s
fi

chown -R "${ZIPKIN_USER}:${ZIPKIN_USER}" "${ZIPKIN_DIR}"

# Systemd unit — Zipkin com Elasticsearch backend
cat <<EOF >/etc/systemd/system/zipkin.service
[Unit]
Description=Zipkin Server
After=network.target elasticsearch.service
Requires=elasticsearch.service

[Service]
Type=simple
User=${ZIPKIN_USER}
Group=${ZIPKIN_USER}
ExecStart=/usr/bin/java -Xms128m -Xmx256m -jar ${ZIPKIN_JAR}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=zipkin

# Storage via Elasticsearch
Environment=STORAGE_TYPE=elasticsearch
Environment=ES_HOSTS=http://127.0.0.1:9200
Environment=ES_INDEX=zipkin
Environment=ES_INDEX_REPLICAS=0
Environment=ES_INDEX_SHARDS=1

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zipkin
systemctl restart zipkin

# Aguarda startup
echo "Aguardando Zipkin iniciar..."
sleep 10
systemctl --no-pager --full status zipkin || true
