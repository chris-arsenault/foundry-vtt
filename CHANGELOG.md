# Changelog

All notable user-visible changes are recorded here.

## v0.1.0 - 2026-08-04

Initial release: a stop-when-idle Foundry VTT server on the ahara platform.

### Game server

- Serve Foundry VTT at https://foundry.ahara.io through the shared ALB with
  an ACM certificate; WAF is bypassed for this host.
- Provision a t4g.medium instance entirely from user data (Node 24, EFS
  mount, systemd services), with instance replacement as the upgrade path
  and a pinned hostname so the Foundry license survives replacement.
- Stop the instance after 60 minutes with no connected players, and
  unconditionally 12 hours after boot.

### Storage

- Persist worlds, modules, and configuration on EFS with daily AWS Backup.
- Serve game media from a public-read S3 bucket via Foundry's native S3
  integration, including in-app uploads.
- Stage the licensed Foundry release zip in a private S3 bucket, installed
  automatically at service start.

### Wake bot

- Add `/foundry start|stop|status` Discord slash commands backed by a Rust
  Lambda at https://api.foundry-vtt.ahara.io, verified against Discord's
  ed25519 signature and authorized by a home-guild allowlist that fails
  closed until configured.

### Platform integration

- Deploy via the shared ahara CI workflow with a registered deployer role;
  configuration and secrets live in SSM under `/ahara/foundry-vtt/`.
