#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl

cat <<'EOF' >/tmp/ishin-gateway-hosts
192.168.56.10 tunnel-1
192.168.56.11 ishin-1
192.168.56.12 ishin-2
192.168.56.21 web-1
192.168.56.31 zipkin-1
EOF

sed -i '/# BEGIN N-GATE LAB HOSTS/,/# END N-GATE LAB HOSTS/d' /etc/hosts
{
  echo "# BEGIN N-GATE LAB HOSTS"
  cat /tmp/ishin-gateway-hosts
  echo "# END N-GATE LAB HOSTS"
} >>/etc/hosts
