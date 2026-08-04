# Discord slash-command wake bot: a Lambda Function URL receives Discord
# interaction webhooks (no API Gateway, no ALB involvement), verifies the
# ed25519 signature, and starts/stops the game server.

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

data "aws_iam_policy_document" "assume_lambda" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "discord_wake" {
  name               = "${local.prefix}-discord-wake"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
}

resource "aws_iam_role_policy_attachment" "discord_wake_logs" {
  role       = aws_iam_role.discord_wake.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "discord_wake" {
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
    sid       = "ReadDiscordConfig"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.discord_public_key.arn]
  }
}

resource "aws_iam_role_policy" "discord_wake" {
  name   = "${local.prefix}-discord-wake"
  role   = aws_iam_role.discord_wake.id
  policy = data.aws_iam_policy_document.discord_wake.json
}

resource "aws_cloudwatch_log_group" "discord_wake" {
  name              = "/aws/lambda/${local.prefix}-discord-wake"
  retention_in_days = 14
}

data "archive_file" "discord_wake" {
  type        = "zip"
  source_file = "${path.module}/lambda/discord/index.mjs"
  output_path = "${path.module}/lambda/discord/discord-wake.zip"
}

resource "aws_lambda_function" "discord_wake" {
  function_name = "${local.prefix}-discord-wake"
  role          = aws_iam_role.discord_wake.arn
  handler       = "index.handler"
  runtime       = "nodejs22.x"
  architectures = ["arm64"]
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.discord_wake.output_path
  source_code_hash = data.archive_file.discord_wake.output_base64sha256

  environment {
    variables = {
      INSTANCE_ID      = aws_instance.server.id
      FOUNDRY_HOSTNAME = local.hostname
      PUBLIC_KEY_PARAM = aws_ssm_parameter.discord_public_key.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.discord_wake]
}

resource "aws_lambda_function_url" "discord_wake" {
  function_name      = aws_lambda_function.discord_wake.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "discord_wake_url" {
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.discord_wake.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
