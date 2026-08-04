# Agent Guide

Infrastructure and Discord wake-bot for a Foundry VTT game server at
foundry.ahara.io on the ahara platform. Foundry is licensed vendor software
staged as a zip in S3; the only code built here is the Rust wake-bot Lambda.

## Read first

| Topic | Link |
| ---- | ---- |
| Repo overview | [README.md](README.md) |
| Architecture | [docs/architecture.md](docs/architecture.md) |
| Operations | [docs/operations.md](docs/operations.md) |
| Architecture decisions | [docs/adr/README.md](docs/adr/README.md) |
| Backlog | [docs/backlog.md](docs/backlog.md) |
| Platform integration | `~/src/ahara/INTEGRATION.md` |

## Critical rules

- Run `make ci` before every commit; do not commit if it fails.
- Deploys go through the shared CI workflow on main. `scripts/deploy.sh` is
  the local-only equivalent; CI must not call it.
- One canonical way per mechanism: no fallback chains (`a || b` installs,
  multi-candidate binary resolution). Hardcode the canonical value and fail
  loudly.
- Secrets are user-set SSM parameters (`PENDING` placeholder +
  `ignore_changes`). Never generate secrets with Terraform; plaintext lands
  in state.
- Reuse ahara platform patterns (shared VPC/ALB, alb-api module, SSM
  discovery) before inventing anything project-local. Deviations require an
  ADR — see [docs/adr/](docs/adr/README.md) for the existing ones.
- Changing `templates/user_data.sh.tpl` replaces the EC2 instance on the
  next apply. Game data on EFS survives; anyone connected is dropped.
- ALB listener priorities 230–231 are claimed in the shared table in
  `ahara/INTEGRATION.md`; claim a new one there before adding a rule.
- Rust follows platform norms: `lambda_http` with manual routing (no Axum
  for platform APIs), clippy `-D warnings -W clippy::cognitive_complexity`.

## Code map

| Path | Purpose |
| ---- | ---- |
| `backend/` | Rust wake-bot Lambda (lib + thin bin) |
| `infrastructure/terraform/` | All Terraform (flat kebab-case files) |
| `infrastructure/terraform/templates/user_data.sh.tpl` | Instance provisioning |
| `infrastructure/terraform/discord.tf` | Wake bot: alb-api module, SSM params |
| `infrastructure/terraform/ec2.tf` | Game server instance, IAM, SG |
| `infrastructure/terraform/efs.tf` | Foundry data filesystem |
| `infrastructure/terraform/s3.tf` | Assets (public-read) + releases buckets |
| `.github/workflows/ci.yml` | Thin caller of the shared ahara workflow |
| `platform.yml` | Platform manifest (stack, rust_artifacts) |

## Commands

| Command | Purpose |
| ---- | ---- |
| `make ci` | Full pre-commit check |
| `make build` | `cargo lambda build --release` |
| `scripts/deploy.sh` | Local build + terraform apply |
| `terraform -chdir=infrastructure/terraform output` | Deployed endpoints/ids |
