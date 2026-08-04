# Operations

## Wake and sleep

`/foundry start|stop|status` in Discord is the normal interface. The server
stops itself after 60 minutes with zero connected players, and unconditionally
720 minutes after boot. While stopped, https://foundry.ahara.io returns the
ALB's error page and the only cost is storage.

## Shell access

No SSH keys exist; use SSM:

```bash
aws ssm start-session --target \
  $(terraform -chdir=infrastructure/terraform output -raw instance_id)
```

## Restarting Foundry

- **Process restart** (seconds): `sudo systemctl restart foundryvtt` over SSM.
- **Instance bounce** (~2 min): `/foundry stop`, wait for stopped, `/foundry
  start`. A stop/start does not re-run provisioning.
- **In-game world switch**: "Return to Setup" from the game sidebar; no
  process restart involved.

## Upgrading Foundry or the OS

Upload the new NodeJS zip to
`s3://foundry-vtt-releases-559098897826/foundryvtt.zip`, then replace the
instance: `terraform apply -replace=aws_instance.server` (or push any
user-data change; user-data changes always replace). Worlds and configuration
on EFS survive; connected players are dropped during the ~2-minute rebuild.
The pinned `foundry-vtt` hostname keeps the license signature valid across
replacements.

## Admin password

The admin key hash lives in `/data/foundry/Config/admin.txt`. To reset:

```bash
sudo systemctl stop foundryvtt
sudo rm -f /data/foundry/Config/admin.txt
sudo systemctl start foundryvtt
```

Order matters — Foundry holds the key in memory and can rewrite the file if
it is deleted while running. With no admin key set, the "Return to Setup"
prompt accepts an empty password. After setting a new one in the setup UI,
mirror it to `/ahara/foundry-vtt/admin-password` in SSM.

## Media uploads

Upload through the file picker's S3 source so media serves from the bucket
instead of accumulating on EFS. Foundry has no setting that disables the
local upload target; the available control is role-gating (in-game Permission
Configuration → "Upload New Files", Gamemaster only). Local uploads land on
EFS and can be moved to S3 after the fact.

## Full reset

Destroys all worlds, installed systems/modules, and the license registration;
S3 assets are untouched:

```bash
sudo systemctl stop foundryvtt
sudo rm -rf /data/foundry/Data /data/foundry/Logs \
  /data/foundry/Config/license.json /data/foundry/Config/admin.txt
sudo systemctl start foundryvtt
```

Keep `Config/options.json` and `Config/aws.json` — provisioning owns them.

## Cost profile

Compute bills only while the server runs (~$0.03/session-hour plus a few
cents of public-IP-free ALB time). Steady state is EFS + EBS + S3 storage,
roughly $4–8/month at typical usage. Always-on would be ~$25/month and needs
platform cost sign-off per ahara-infra conventions.
