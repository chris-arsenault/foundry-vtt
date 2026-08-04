# Architecture

A single Foundry VTT server for one game group, built so the machine runs only
during sessions while worlds, media, and configuration persist independently
of any particular instance.

## Game server

`t4g.medium` EC2 instance (AL2023 arm64, Node 24) in a shared-VPC private
subnet, provisioned entirely by
`infrastructure/terraform/templates/user_data.sh.tpl`. The instance is a plain
`aws_instance` with `instance_initiated_shutdown_behavior = "stop"` — see
[ADR-0001](adr/0001-stop-when-idle-plain-instance.md). Foundry runs as the
`foundry` system user under systemd (`foundryvtt.service`), launched by
`/usr/local/bin/foundry-run` with `--dataPath=/data/foundry`. The Foundry
application zip is pulled from the releases bucket by an idempotent
`ExecStartPre` install script that retries every minute until the zip is
staged. The hostname is pinned to `foundry-vtt` so Foundry's machine-bound
license signature survives instance replacement.

Two systemd units stop the machine: `foundry-idle.timer` polls
`localhost:30000/api/status` each minute and shuts down after 60 consecutive
minutes with zero connected players; `foundry-max-uptime.service` schedules a
hard stop 720 minutes after boot. Both install before any fallible
provisioning step, so a broken provision cannot leave the instance running
indefinitely.

## Edge

The shared ahara ALB terminates TLS with an SNI ACM certificate for
`foundry.ahara.io` and forwards (listener priority 230, no auth action —
Foundry runs its own admin-key/player-password auth) to a target group on
instance port 30000, health-checked on `/api/status`. WAF is fully bypassed
for this host: the `FoundryVttBypass` priority-0 allow rule in ahara-infra
`network/waf.tf`. DNS is a static alias to the ALB, so wake/sleep cycles
never touch Route53.

## Data

Foundry's data directory (worlds, modules, configuration, license) lives on
EFS mounted at `/data`, single mount target pinned to the instance's subnet,
lifecycle policy to Infrequent Access, daily AWS Backup — see
[ADR-0002](adr/0002-game-data-on-efs.md). The instance root volume is
disposable. `Config/options.json` is seeded once and then owned by Foundry's
setup UI, except `awsConfig`, which provisioning re-enforces to
`/data/foundry/Config/aws.json` (a region-only file so the AWS SDK credential
chain reaches the instance role).

## Media assets

Foundry's native S3 integration serves game media directly from the
public-read `foundry-vtt-assets-<account id>` bucket — see
[ADR-0005](adr/0005-public-read-assets-bucket.md). The bucket accepts
Foundry's public-read upload ACLs (`BucketOwnerPreferred` ownership, ACL
blocks disabled) and the instance role carries `s3:PutObjectAcl` alongside
read/write. The private `foundry-vtt-releases-<account id>` bucket stages the
licensed Foundry zip.

## Wake bot

`/foundry start|stop|status` Discord slash commands post to a Rust
`lambda_http` Lambda behind the shared ALB at `api.foundry-vtt.ahara.io`
(alb-api module, listener priority 231) — see
[ADR-0003](adr/0003-wake-bot-behind-shared-alb.md). Requests are
authenticated by Discord's ed25519 signature and authorized by a guild
allowlist — see [ADR-0004](adr/0004-guild-allowlist-authorization.md). The
Lambda's IAM is scoped to describe/start/stop instances tagged
`Project=foundry-vtt` and read the `/ahara/foundry-vtt/*` SSM parameters.

## Configuration and secrets

All runtime configuration is SSM parameters under `/ahara/foundry-vtt/`:

| Parameter | Type | Set by |
| ---- | ---- | ---- |
| `discord-public-key` | String | operator, from the Discord app |
| `discord-guild-id` | String | operator, home server snowflake |
| `discord-client-secret` | SecureString | operator |
| `discord-bot-token` | SecureString | operator |
| `admin-password` | SecureString | operator, mirrors the Foundry admin key |

Secret parameters are created as `PENDING` placeholders with
`ignore_changes`; Terraform never generates secret values.

## Platform integration

State key `projects/foundry-vtt.tfstate`; deployer role
`deployer-foundry-vtt` registered in
`ahara-infra/infrastructure/terraform/control/project-foundry-vtt.tf` (the
`efs` and `s3-bucket-policy` policy primitives were added to the platform
policy library for this project). ALB listener priorities 230–231 are claimed
in the shared table in `ahara/INTEGRATION.md`. CI is the shared ahara
workflow; deploys run on pushes to main.
