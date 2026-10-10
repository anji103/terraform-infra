#!/bin/bash
set -euxo pipefail
dnf update -y
dnf install -y nginx
cat > /usr/share/nginx/html/index.html <<'HTML'
<!doctype html>
<html><head><title>DevOps Practical</title></head>
<body><h1>AWS Terraform deployment is running</h1>
<p>Served by an EC2 instance in a private subnet behind an HTTPS ALB.</p>
<p><a href="/health">Health check</a></p></body></html>
HTML
cat > /usr/share/nginx/html/health <<'HEALTH'
healthy
HEALTH
systemctl enable nginx
systemctl start nginx
