# 0001 — Stop-when-idle plain EC2 instance

- Status: Accepted
- Date: 2026-08-04

## Context

A game table uses the server a handful of hours per month. The ahara platform
convention for permanent instances is an ASG-of-1 with a launch template,
pinned ENI, and nightly instance refresh; the platform also has a strict
cost-consciousness norm.

## Decision

Run a plain `aws_instance` with `instance_initiated_shutdown_behavior =
"stop"`, stopped except during sessions. On-instance systemd units stop the
machine after 60 idle minutes and unconditionally after 12 hours.

## Alternatives considered

- **Platform ASG-of-1 pattern** — refresh and template versioning for free,
  but an ASG replaces a stopped instance as unhealthy, which is incompatible
  with stop-when-idle; suppressing its health processes defeats the pattern.
- **Always-on instance** — no wake ceremony; ~$25/month and requires platform
  cost sign-off for no session-time benefit.
- **Spot instance** — cheapest compute; a 2-minute interruption warning
  mid-session is unacceptable for a live game.
- **Fargate + EFS** — no instance management; costs more than stopped EC2
  and adds moving parts without removing the wake problem.

## Consequences

Compute cost rounds to zero. Instance replacement is the upgrade mechanism
(`user_data_replace_on_change = true`), so provisioning must be safe to
re-run and anything the instance must survive lives off-instance. The
idle-stop and max-uptime units install before any fallible provisioning step
so a broken provision cannot leave the machine running.
