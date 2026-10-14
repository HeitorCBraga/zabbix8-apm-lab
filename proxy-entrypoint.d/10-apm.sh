#!/bin/sh
set -e
if ! grep -q '^StartAPMCollectors=' /etc/zabbix/zabbix_proxy.conf 2>/dev/null; then
  cat >> /etc/zabbix/zabbix_proxy.conf <<'EOF'
StartAPMCollectors=1
APMListenIP=0.0.0.0
APMListenPort=4317
EOF
fi
