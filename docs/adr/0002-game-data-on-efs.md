# 0002 — Game data on EFS

- Status: Accepted
- Date: 2026-08-04

## Context

Foundry's data directory (worlds, modules, configuration, license) must
survive instance replacement, which ADR-0001 makes the routine upgrade path.

## Decision

Mount EFS at `/data` and run Foundry with `--dataPath=/data/foundry`. Single
mount target pinned to the instance's subnet, lifecycle policy to Infrequent
Access, daily AWS Backup. The instance root EBS volume is disposable.

## Alternatives considered

- **Persistent EBS data volume** — cheaper per GB (~4×), but ties the data to
  one AZ and requires detach/attach choreography on every instance
  replacement; replacement stops being a single `-replace` apply.
- **Data on the root volume + snapshots** — simplest, but couples Foundry/OS
  upgrades to data migration and makes replacement destructive.

## Consequences

Instance replacement never touches game data. Storage costs ~$0.30/GB-month
(less after IA transition) on a data set kept small by serving media from S3.
The instance and mount target share one AZ by construction
(`local.subnet_id`), so cross-AZ mount latency cannot occur, and moving AZs
is a deliberate two-resource change.
