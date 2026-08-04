# Discord slash-command wake bot: the platform-standard alb-api shape — Rust
# lambda_http Lambda behind the shared ALB at api.foundry-vtt.ahara.io. The
# route is unauthenticated at the ALB because Discord signs every request with
# its ed25519 application key, verified in the handler.

# Set after creating the Discord application:
#   aws ssm put-parameter --name /ahara/foundry-vtt/discord-public-key \
#     --type String --value <hex key> --overwrite
resource "aws_ssm_parameter" "discord_public_key" {
  name  = "${local.ssm_prefix}/discord-public-key"
  type  = "String"
  value = "PENDING"

  lifecycle {
    ignore_changes = [value]
  }
}

# The only Discord server allowed to command the instance. A valid signature
# proves the request came from Discord for this application, not that it came
# from our server — anyone who installs the app elsewhere still produces
# validly signed interactions, so the handler rejects any other guild_id.
# While PENDING, all commands are rejected (fails closed).
#   aws ssm put-parameter --name /ahara/foundry-vtt/discord-guild-id \
#     --type String --value <server id> --overwrite
resource "aws_ssm_parameter" "discord_guild_id" {
  name  = "${local.ssm_prefix}/discord-guild-id"
  type  = "String"
  value = "PENDING"

  lifecycle {
    ignore_changes = [value]
  }
}

data "aws_iam_policy_document" "wake" {
  # DescribeInstances does not support resource-level scoping.
  statement {
    sid       = "DescribeInstances"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  statement {
    sid       = "StartStopFoundry"
    actions   = ["ec2:StartInstances", "ec2:StopInstances"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [local.prefix]
    }
  }

  statement {
    sid     = "ReadDiscordConfig"
    actions = ["ssm:GetParameter"]
    resources = [
      aws_ssm_parameter.discord_public_key.arn,
      aws_ssm_parameter.discord_guild_id.arn,
    ]
  }
}

module "wake_api" {
  source   = "git::https://github.com/chris-arsenault/ahara-tf-patterns.git//modules/alb-api"
  prefix   = local.prefix
  hostname = local.wake_api_hostname

  vpc = module.ctx.vpc
  alb = module.ctx.alb

  iam_policy = [data.aws_iam_policy_document.wake.json]

  environment = {
    INSTANCE_ID      = aws_instance.server.id
    FOUNDRY_HOSTNAME = local.hostname
    PUBLIC_KEY_PARAM = aws_ssm_parameter.discord_public_key.name
    GUILD_ID_PARAM   = aws_ssm_parameter.discord_guild_id.name
  }

  lambdas = {
    wake = {
      binary = "${path.root}/../../backend/target/lambda/discord-wake/bootstrap"
      routes = [
        {
          priority      = local.wake_api_listener_rule_priority
          paths         = ["/*"]
          authenticated = false
        }
      ]
    }
  }
}
