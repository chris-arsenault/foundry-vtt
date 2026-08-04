# foundry-vtt

Infrastructure for a [Foundry Virtual Tabletop](https://foundryvtt.com/) server
at https://foundry.ahara.io, hosted in the ahara AWS platform. The server stops
itself between game sessions and is woken by a Discord slash command, so the
steady-state cost is storage only (~$4–8/month all-in).

## Architecture

- **Server**: `t4g.medium` EC2 instance (AL2023 arm64, Node 22) in the shared
  VPC's private subnet, behind the shared ALB at `foundry.ahara.io` (SNI ACM
  cert, no auth action — Foundry handles its own logins). WAF is bypassed for
  this host (ahara-infra `network/waf.tf`).
- **Data**: Foundry's data directory (worlds, modules, config) on EFS with
  daily AWS Backup. The instance root volume is disposable; replace the
  instance freely, data survives.
- **Assets**: Foundry's native S3 media integration against the public-read
  `foundry-vtt-assets-<account id>` bucket (instance-profile credentials, no
  stored keys).
- **Wake/sleep**: a Discord bot (`/foundry start|stop|status`) posts to a
  Lambda Function URL that starts/stops the instance. On the instance, a
  watchdog polls `/api/status` every minute and stops the machine after 60
  minutes with zero connected players; a hard cap stops it 12 hours after boot
  regardless.

## First-time setup

1. **Stage the Foundry release** (license-gated download, so it is done once by
   hand). Get the *Linux/NodeJS* zip from foundryvtt.com, then:

   ```bash
   aws s3 cp FoundryVTT-*.zip s3://foundry-vtt-releases-559098897826/foundryvtt.zip
   ```

2. **Create the Discord application** (discord.com/developers): note the
   *Public Key* and *Application ID*, then store the key:

   ```bash
   aws ssm put-parameter --name /ahara/foundry-vtt/discord-public-key \
     --type String --value <public key hex> --overwrite
   ```

3. **Deploy**: `scripts/deploy.sh` (or push to main). Note the
   `discord_interactions_url` output.

4. **Point Discord at the Lambda**: set the Interactions Endpoint URL in the
   Discord app to that output. Then register the slash command (run via
   `with-cred --` in this environment, or set `DISCORD_BOT_TOKEN` yourself):

   ```bash
   curl -X POST \
     -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
     -H "Content-Type: application/json" \
     "https://discord.com/api/v10/applications/<APP_ID>/commands" \
     -d '{
       "name": "foundry",
       "description": "Manage the Foundry VTT server",
       "options": [
         {"type": 1, "name": "start",  "description": "Wake the server"},
         {"type": 1, "name": "stop",   "description": "Stop the server"},
         {"type": 1, "name": "status", "description": "Server and world status"}
       ]
     }'
   ```

5. **First boot**: `/foundry start` in Discord, wait ~2 minutes, open
   https://foundry.ahara.io, enter the license key, and create the world.
   Configure S3 assets under Setup → filepicker (bucket
   `foundry-vtt-assets-559098897826`).

## Operations

- `/foundry start|stop|status` in Discord is the normal interface.
- Shell access: `aws ssm start-session --target $(terraform -chdir=infrastructure/terraform output -raw instance_id)`
  (no SSH keys exist).
- **Upgrading Foundry**: upload the new zip to the releases bucket, then
  `terraform apply -replace=aws_instance.server` — the instance rebuilds from
  user-data, worlds and config are untouched on EFS.
- Player data never expires from a stopped server; stopping mid-session just
  disconnects players until the next `/foundry start`.

## Platform integration

Follows `~/src/ahara/INTEGRATION.md`: state key `projects/foundry-vtt.tfstate`,
ALB listener priority **230**, deployer role in
`ahara-infra/infrastructure/terraform/control/project-foundry-vtt.tf`.
