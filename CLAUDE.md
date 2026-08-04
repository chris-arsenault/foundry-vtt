# foundry-vtt

Terraform-only repo hosting a Foundry Virtual Tabletop server at
foundry.ahara.io on the ahara platform. No application code is built here;
Foundry itself is licensed vendor software staged as a zip in S3.

## Architecture

- **Server**: plain `aws_instance` (t4g.medium, AL2023 arm64) in the shared
  VPC private subnet. Deliberately NOT the platform's ASG-of-1 pattern: the
  instance stops between sessions and an ASG would replace a stopped instance.
  `instance_initiated_shutdown_behavior = "stop"`; all provisioning is in
  `infrastructure/terraform/templates/user_data.sh.tpl`.
- **Edge**: shared ALB, SNI cert, listener rule priority 230, host
  `foundry.ahara.io`, forward with no auth action (Foundry has its own auth).
  WAF is fully bypassed for this host — rule `FoundryVttBypass` in
  ahara-infra `network/waf.tf`.
- **Data**: EFS at `/data` (mount target pinned to the same AZ/subnet as the
  instance), daily AWS Backup. Instance root EBS is disposable.
- **Assets**: `foundry-vtt-assets` S3 bucket is public-read — a deliberate
  exception to the platform CloudFront-OAC posture because Foundry's S3
  integration serves direct object URLs to players. Game media only.
- **Wake**: `/foundry start|stop|status` Discord slash command → Lambda
  Function URL (`infrastructure/terraform/lambda/discord/index.mjs`, nodejs22,
  ed25519 verify via `/ahara/foundry-vtt/discord-public-key` SSM param).
- **Sleep**: on-instance systemd timer stops the machine after 60 idle
  minutes (zero `users` from `http://localhost:30000/api/status`); a second
  unit hard-stops 720 minutes after boot.

## Build & Deploy

```bash
make ci            # terraform fmt check + lambda syntax check
scripts/deploy.sh  # terraform init + apply (CI does the same on main)
```

## Key decisions

- Stop-when-idle over always-on: sessions total ~16 h/month; compute is
  pennies while EFS/EBS/S3 dominate the ~$4–8/mo cost.
- EFS over EBS data volume: instance replacement (Foundry/OS upgrades) never
  touches game data; `terraform apply -replace=aws_instance.server` is the
  upgrade path.
- Spot rejected: a 2-minute interruption warning mid-session is unacceptable.
- TrueNAS rejected: serves people other than the platform owner
  (ahara TRUENAS-DEPLOY.md placement rule).

## Platform integration

See `~/src/ahara/INTEGRATION.md`. State key `projects/foundry-vtt.tfstate`;
deployer role registered in
`ahara-infra/infrastructure/terraform/control/project-foundry-vtt.tf`
(includes the `efs` and `s3-bucket-policy` policy modules added for this
project).

## Pre-commit CI check

**Run `make ci` before committing any change.** This runs the same lint,
format, typecheck, and test steps as GitHub Actions. Do not commit if it fails.
