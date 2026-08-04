#!/bin/bash
# First-boot provisioning for the Foundry VTT server (AL2023 arm64).
# Terraform template: double-dollar braces are shell, single are Terraform.
set -euxo pipefail

dnf -y install nodejs22 unzip jq amazon-efs-utils

NODE_BIN=$(command -v node-22 || command -v node22 || command -v node)

# ── Foundry data on EFS ─────────────────────────────────────
mkdir -p /data
if ! grep -q '^${efs_id}:/ /data ' /etc/fstab; then
  echo '${efs_id}:/ /data efs _netdev,tls 0 0' >> /etc/fstab
fi
mount -a

useradd --system --home-dir /data/foundry --shell /sbin/nologin foundry || true
mkdir -p /data/foundry/Config

# ── Foundry application (disposable; data stays on EFS) ─────
if [ ! -d /opt/foundryvtt ]; then
  aws s3 cp 's3://${releases_bucket}/${release_key}' /tmp/foundryvtt.zip
  mkdir -p /opt/foundryvtt
  unzip -oq /tmp/foundryvtt.zip -d /opt/foundryvtt
  rm -f /tmp/foundryvtt.zip
fi

MAIN_JS=$(find /opt/foundryvtt -maxdepth 5 -type f \( -name main.mjs -o -name main.js \) -path '*resources/app*' | head -1)
if [ -z "$${MAIN_JS}" ]; then
  MAIN_JS=$(find /opt/foundryvtt -maxdepth 2 -type f \( -name main.mjs -o -name main.js \) | head -1)
fi

# Seed options.json once; afterwards Foundry's setup UI owns it (it lives on EFS).
if [ ! -f /data/foundry/Config/options.json ]; then
  cat > /data/foundry/Config/options.json <<EOF
{
  "port": ${foundry_port},
  "upnp": false,
  "hostname": "${hostname}",
  "proxySSL": true,
  "proxyPort": 443,
  "awsConfig": true,
  "minifyStaticFiles": true
}
EOF
fi
chown -R foundry:foundry /data/foundry

# ── Foundry service ─────────────────────────────────────────
cat > /etc/systemd/system/foundryvtt.service <<EOF
[Unit]
Description=Foundry Virtual Tabletop
After=network-online.target remote-fs.target
Wants=network-online.target
RequiresMountsFor=/data

[Service]
User=foundry
Environment=AWS_REGION=${region}
ExecStart=$${NODE_BIN} $${MAIN_JS} --dataPath=/data/foundry
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# ── Idle watchdog: stop after ${idle_stop_minutes} min with zero players ────
cat > /usr/local/bin/foundry-idle-check <<'WATCHDOG'
#!/bin/bash
# Counts consecutive idle minutes via Foundry's /api/status; a fetch failure
# (Foundry down/starting) also counts as idle. Shutdown stops (not terminates)
# the instance per instance_initiated_shutdown_behavior.
STATE=/run/foundry-idle-minutes
THRESHOLD=$${1:?idle threshold minutes}
COUNT=$(cat "$${STATE}" 2>/dev/null || echo 0)
USERS=$(curl -sf --max-time 5 "http://localhost:$${2:?foundry port}/api/status" | jq -r '.users // 0' 2>/dev/null || echo "")
if [ -n "$${USERS}" ] && [ "$${USERS}" != "0" ] && [ "$${USERS}" != "null" ]; then
  COUNT=0
else
  COUNT=$((COUNT + 1))
fi
echo "$${COUNT}" > "$${STATE}"
if [ "$${COUNT}" -ge "$${THRESHOLD}" ]; then
  logger -t foundry-idle "no players for $${COUNT} minutes; stopping instance"
  shutdown -h now
fi
WATCHDOG
chmod +x /usr/local/bin/foundry-idle-check

cat > /etc/systemd/system/foundry-idle.service <<EOF
[Unit]
Description=Stop the instance after ${idle_stop_minutes} idle minutes

[Service]
Type=oneshot
ExecStart=/usr/local/bin/foundry-idle-check ${idle_stop_minutes} ${foundry_port}
EOF

cat > /etc/systemd/system/foundry-idle.timer <<EOF
[Unit]
Description=Per-minute Foundry idle check

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

# ── Hard cap: never run longer than ${max_uptime_minutes} minutes ──────────
cat > /etc/systemd/system/foundry-max-uptime.service <<EOF
[Unit]
Description=Hard stop ${max_uptime_minutes} minutes after boot
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/shutdown -h +${max_uptime_minutes}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now foundryvtt.service foundry-idle.timer foundry-max-uptime.service
