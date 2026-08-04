# Backlog

Planned-but-not-built work. Each item is a positive assertion of future-state
behavior.

## Observability

- Emit wake-bot and game-server telemetry to the platform OTLP stack with
  `ahara_*` metric naming, and ship a Grafana dashboard declared under
  `observability.dashboards` in `platform.yml`.

## Operations

- Document a media-migration procedure that moves locally-uploaded assets
  from EFS into the S3 assets bucket.
