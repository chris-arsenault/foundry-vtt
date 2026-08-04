#!/bin/bash
# First-boot provisioning for the Foundry VTT server (AL2023 arm64).
# Terraform template: double-dollar braces are shell, single are Terraform.
#
# Ordering matters: the auto-stop units are installed before anything that can
# fail (EFS mount, S3 fetch), so a broken provision can never leave the
# instance running indefinitely.
set -euxo pipefail

dnf -y install nodejs24 unzip jq amazon-efs-utils

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

systemctl daemon-reload
systemctl enable --now foundry-max-uptime.service foundry-idle.timer

# ── Foundry data on EFS ─────────────────────────────────────
mkdir -p /data
if ! grep -q '^${efs_id}:/ /data ' /etc/fstab; then
  echo '${efs_id}:/ /data efs _netdev,tls 0 0' >> /etc/fstab
fi
mount -a

useradd --system --home-dir /data/foundry --shell /sbin/nologin foundry || true
mkdir -p /data/foundry/Config

# AWS config for Foundry's S3 media integration: region only, no credential
# keys, so the SDK falls through to the instance role. ("awsConfig": true
# would resolve from environment variables only and never see the role.)
cat > /data/foundry/Config/aws.json <<EOF
{ "region": "${region}" }
EOF

# Seed options.json once; afterwards Foundry's setup UI owns it (it lives on EFS).
if [ ! -f /data/foundry/Config/options.json ]; then
  cat > /data/foundry/Config/options.json <<EOF
{
  "port": ${foundry_port},
  "upnp": false,
  "hostname": "${hostname}",
  "proxySSL": true,
  "proxyPort": 443,
  "awsConfig": "/data/foundry/Config/aws.json",
  "minifyStaticFiles": true
}
EOF
fi

# awsConfig is infrastructure-owned: enforce it on every provision without
# touching the UI-owned settings around it.
OPTIONS_TMP=$(mktemp)
jq '.awsConfig = "/data/foundry/Config/aws.json"' /data/foundry/Config/options.json > "$${OPTIONS_TMP}"
mv "$${OPTIONS_TMP}" /data/foundry/Config/options.json

chown -R foundry:foundry /data/foundry

# ── Foundry install + run helpers ───────────────────────────
# Installation happens at service start (idempotent), not at provision time:
# if the release zip is not staged yet, the service retries every minute
# instead of leaving a half-provisioned instance behind.
cat > /usr/local/bin/foundry-install <<'INSTALL'
#!/bin/bash
set -euo pipefail
if [ -d /opt/foundryvtt ]; then
  exit 0
fi
aws s3 cp "s3://$${1:?releases bucket}/$${2:?release key}" /tmp/foundryvtt.zip
mkdir -p /opt/foundryvtt
unzip -oq /tmp/foundryvtt.zip -d /opt/foundryvtt
rm -f /tmp/foundryvtt.zip
INSTALL
chmod +x /usr/local/bin/foundry-install

cat > /usr/local/bin/foundry-run <<'RUN'
#!/bin/bash
set -euo pipefail
# /usr/bin/node-24 is the namespaced AL2023 binary; it always resolves to
# Node 24 regardless of the `alternatives` default.
MAIN_JS=$(find /opt/foundryvtt -maxdepth 5 -type f \( -name main.mjs -o -name main.js \) -path '*resources/app*' | head -1)
if [ -z "$${MAIN_JS}" ]; then
  MAIN_JS=$(find /opt/foundryvtt -maxdepth 2 -type f \( -name main.mjs -o -name main.js \) | head -1)
fi
exec /usr/bin/node-24 "$${MAIN_JS}" --dataPath=/data/foundry
RUN
chmod +x /usr/local/bin/foundry-run

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
ExecStartPre=+/usr/local/bin/foundry-install ${releases_bucket} ${release_key}
ExecStart=/usr/local/bin/foundry-run
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now foundryvtt.service
