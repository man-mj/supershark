#!/bin/bash
set -e

clear
echo "====================================="
echo "  ยินดีต้อนรับสู่การติดตั้งระบบเช็คออนไลน์ SSH"
echo "        By.Duck VPN"
echo "====================================="
echo ""
echo "กำลังเริ่มต้นการติดตั้ง กรุณารอสักครู่..."
sleep 2

# ===== CONFIG =====
PORT=8888
LIMIT=250
OUTDIR="/var/www/html/server"
OUTFILE="$OUTDIR/online_app.json"
# ==================

# 1) Install Apache
sudo apt update -y
sudo apt install -y apache2

# 2) Ensure Apache listens on PORT (DO NOT overwrite Listen 80)
if ! grep -qE "^[[:space:]]*Listen[[:space:]]+${PORT}([[:space:]]|$)" /etc/apache2/ports.conf; then
  echo "Listen ${PORT}" | sudo tee -a /etc/apache2/ports.conf >/dev/null
fi

# 3) Create a dedicated VirtualHost for PORT (DO NOT replace 000-default.conf)
sudo bash -c "cat > /etc/apache2/sites-available/online-${PORT}.conf <<EOF
<VirtualHost *:${PORT}>
    DocumentRoot /var/www/html
    ErrorLog \${APACHE_LOG_DIR}/online-${PORT}-error.log
    CustomLog \${APACHE_LOG_DIR}/online-${PORT}-access.log combined
</VirtualHost>
EOF"

sudo a2ensite "online-${PORT}.conf" >/dev/null || true

# 4) Web directory
sudo mkdir -p "${OUTDIR}"
sudo chown -R www-data:www-data "${OUTDIR}"
sudo chmod -R 755 "${OUTDIR}"

# 5) Restart Apache
sudo systemctl restart apache2
sudo systemctl --no-pager --full status apache2 | head -n 30 || true

# 6) Create counter script
sudo bash -c "cat > /usr/local/bin/count_online_users.sh <<'EOF'
#!/bin/bash
set -e

PORT=8888
LIMIT=250
OUTDIR=\"/var/www/html/server\"
OUTFILE=\"\$OUTDIR/online_app.json\"

mkdir -p \"\$OUTDIR\"

count_online_users() {
  ssh_online=\$(ps aux | grep \"[s]shd\" | grep -v root | grep -c priv || true)

  # OpenVPN status (CLIENT_LIST lines)
  if [[ -f /etc/openvpn/openvpn-status.log ]]; then
    openvpn_online=\$(grep -c \"^CLIENT_LIST\" /etc/openvpn/openvpn-status.log || true)
  else
    openvpn_online=0
  fi

  # Dropbear sessions (process count)
  if pgrep -x dropbear >/dev/null 2>&1; then
    dropbear_online=\$(ps aux | grep \"[d]ropbear\" | wc -l || true)
  else
    dropbear_online=0
  fi

  total_online=\$((ssh_online + openvpn_online + dropbear_online))
  echo \"[{\\\"onlines\\\":\\\"\$total_online\\\",\\\"limite\\\":\\\"\$LIMIT\\\"}]\" > \"\$OUTFILE\"
  echo \"Online: \$total_online / \$LIMIT\"
}

while true; do
  count_online_users
  sleep 15
done
EOF"

sudo chmod +x /usr/local/bin/count_online_users.sh

# 7) systemd service (restart always)
sudo bash -c "cat > /etc/systemd/system/count_online_users.service <<EOF
[Unit]
Description=Count Online Users Service
After=network.target apache2.service
Wants=apache2.service

[Service]
Type=simple
ExecStart=/usr/local/bin/count_online_users.sh
Restart=always
RestartSec=2
User=root

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable --now count_online_users.service

echo ""
echo "✅ ติดตั้งเสร็จแล้ว"
echo "API: http://YOUR_IP:${PORT}/server/online_app.json"
echo "เช็ค service: systemctl status count_online_users.service"
