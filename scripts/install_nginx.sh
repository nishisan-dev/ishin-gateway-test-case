#!/usr/bin/env bash
set -euo pipefail

NODE_NAME="${1:?missing node name}"

export DEBIAN_FRONTEND=noninteractive

apt-get install -y nginx

cat <<EOF >/var/www/html/index.html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>${NODE_NAME}</title>
</head>
<body>
  <h1>${NODE_NAME}</h1>
  <p>Nginx provisioned by Vagrant.</p>
  <p>If you are seeing this page through ishin-gateway, the reverse proxy is working.</p>
</body>
</html>
EOF

cat <<'EOF' >/etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html;
    server_name _;

    location /health {
        default_type text/plain;
        return 200 "ok\n";
    }

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

systemctl enable nginx
systemctl restart nginx
systemctl --no-pager --full status nginx
