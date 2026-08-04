locals {
  prefix   = "foundry-vtt"
  hostname = "foundry.ahara.io"

  foundry_port = 30000

  # Claimed in the shared listener-priority table in ahara/INTEGRATION.md.
  # athena-s3-web-shell reserves 220-229; tsonu-music starts at 240.
  listener_rule_priority = 230

  assets_bucket   = "${local.prefix}-assets"
  releases_bucket = "${local.prefix}-releases"
  release_key     = "foundryvtt.zip"

  ssm_prefix = "/ahara/foundry-vtt"

  # The instance and the EFS mount target must share an AZ; pin both to one
  # deterministic private subnet.
  subnet_id = sort(module.ctx.vpc.private_subnet_ids)[0]

  # Auto-stop tuning (minutes).
  idle_stop_minutes  = 60
  max_uptime_minutes = 720
}
