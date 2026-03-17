#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

NODE_NAME="${1:?missing node name}"
NODE_IP="${2:?missing node ip}"
UPSTREAM_IP="${3:?missing upstream ip}"
UPSTREAM_PORT="${4:-80}"
CLUSTER_SEEDS_CSV="${5:?missing cluster seeds}"
NGATE_VERSION="3.1.2"
PACKAGE_URL="https://github.com/nishisan-dev/n-gate/releases/download/v${NGATE_VERSION}/n-gate_${NGATE_VERSION}_all.deb"
PACKAGE_PATH="/tmp/n-gate_${NGATE_VERSION}_all.deb"
CLUSTER_DATA_DIR="/var/log/n-gate/ngrid-data"
DASHBOARD_DATA_DIR="/var/lib/n-gate"
RUNTIME_TMP_DIR="/var/log/n-gate/tmp"

if ! dpkg-query -W -f='${Version}' n-gate 2>/dev/null | grep -qx "${NGATE_VERSION}"; then
  apt-get install -y openjdk-21-jre-headless
  curl -fL "${PACKAGE_URL}" -o "${PACKAGE_PATH}"
  apt-get install -y "${PACKAGE_PATH}"
fi

mkdir -p "${CLUSTER_DATA_DIR}" "${RUNTIME_TMP_DIR}" "${DASHBOARD_DATA_DIR}"
chown -R n-gate:n-gate /var/log/n-gate "${DASHBOARD_DATA_DIR}"

SEEDS_YAML=""
IFS=',' read -ra CLUSTER_SEEDS <<<"${CLUSTER_SEEDS_CSV}"
for seed in "${CLUSTER_SEEDS[@]}"; do
  SEEDS_YAML="${SEEDS_YAML}"$'\n'"    - \"${seed}\""
done

mkdir -p /etc/systemd/system/n-gate.service.d

cat <<EOF >/etc/systemd/system/n-gate.service.d/override.conf
[Service]
Environment=NGATE_CONFIG=/etc/n-gate/adapter.yaml
Environment=NGATE_CLUSTER_NODE_ID=${NODE_NAME}
Environment=TMPDIR=${RUNTIME_TMP_DIR}
Environment=ZIPKIN_ENDPOINT=http://zipkin-1:9411/api/v2/spans
ExecStart=
ExecStart=/usr/bin/java -Djava.io.tmpdir=${RUNTIME_TMP_DIR} -Dlog4j.configurationFile=/etc/n-gate/log4j2.xml -jar /opt/n-gate/n-gate.jar
ReadWritePaths=/var/log/n-gate
ReadWritePaths=/var/lib/n-gate
EOF

cat <<EOF >/etc/n-gate/adapter.yaml
---
endpoints:
  default:
    rulesBasePath: "/etc/n-gate/rules"

    listeners:
      http:
        listenAddress: "0.0.0.0"
        listenPort: 9090
        ssl: false
        scriptOnly: false
        defaultBackend: "backend-1"
        secured: false
        urlContexts:
          default:
            context: "/*"
            method: "ANY"
            ruleMapping: "default/Rules.groovy"

    backends:
      backend-1:
        backendName: "${NODE_NAME}-backend"
        members:
          - url: "http://${UPSTREAM_IP}:${UPSTREAM_PORT}"
            weight: 1

    ruleMapping: "default/Rules.groovy"
    ruleMappingThreads: 1
    socketTimeout: 30
    jettyMinThreads: 16
    jettyMaxThreads: 200
    jettyIdleTimeout: 120000
    connectionPoolSize: 128
    connectionPoolKeepAliveMinutes: 5
    dispatcherMaxRequests: 256
    dispatcherMaxRequestsPerHost: 128

cluster:
  enabled: true
  host: "${NODE_IP}"
  port: 7100
  clusterName: "ngate-cluster"
  seeds:${SEEDS_YAML}
  replicationFactor: 2
  dataDirectory: "${CLUSTER_DATA_DIR}"

admin:
  enabled: true
  apiKey: "nishisan"

dashboard:
  enabled: true
  port: 9200
  bindAddress: "0.0.0.0"
  allowedIps:
    - "127.0.0.1"
    - "::1"
    - "10.0.0.0/8"
    - "192.168.0.0/16"
  storage:
    path: "${DASHBOARD_DATA_DIR}"
    retentionHours: 24
    scrapeIntervalSeconds: 15
  zipkin:
    enabled: true
    baseUrl: "http://zipkin-1:9411"
EOF

mkdir -p /etc/n-gate/rules/default

cat <<'EOF' >/etc/n-gate/rules/default/Rules.groovy
/**
 * Pass-through rule: every request is forwarded to the configured default backend.
 */
EOF

systemctl daemon-reload
systemctl enable n-gate
systemctl restart n-gate

sleep 2
systemctl --no-pager --full status n-gate
