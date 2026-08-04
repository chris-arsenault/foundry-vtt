# Plain aws_instance rather than the platform's ASG-of-1 module: the server is
# stopped between game sessions, and an ASG would treat a stopped instance as
# unhealthy and replace it. Follows the ahara-infra bastion precedent
# (instance_initiated_shutdown_behavior = "stop" + on-instance shutdown timers).

data "aws_ssm_parameter" "al2023_ami_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "server" {
  name               = "${local.prefix}-server"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_instance_profile" "server" {
  name = "${local.prefix}-server"
  role = aws_iam_role.server.name
}

resource "aws_iam_role_policy_attachment" "server_ssm" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "server" {
  # Foundry's S3 media integration discovers buckets, then reads/writes assets.
  statement {
    sid       = "ListBuckets"
    actions   = ["s3:ListAllMyBuckets", "s3:GetBucketLocation"]
    resources = ["*"]
  }

  statement {
    sid     = "AssetsReadWrite"
    actions = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      aws_s3_bucket.assets.arn,
      "${aws_s3_bucket.assets.arn}/*",
    ]
  }

  statement {
    sid     = "ReleasesRead"
    actions = ["s3:ListBucket", "s3:GetObject"]
    resources = [
      aws_s3_bucket.releases.arn,
      "${aws_s3_bucket.releases.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "server" {
  name   = "${local.prefix}-server"
  role   = aws_iam_role.server.id
  policy = data.aws_iam_policy_document.server.json
}

resource "aws_security_group" "server" {
  name        = "${local.prefix}-server-sg"
  description = "Foundry VTT server: game traffic from the shared ALB only"
  vpc_id      = module.ctx.vpc.vpc_id

  tags = {
    Name = "${local.prefix}-server-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "server_from_alb" {
  security_group_id            = aws_security_group.server.id
  description                  = "Foundry HTTP/WebSocket from the shared ALB"
  ip_protocol                  = "tcp"
  from_port                    = local.foundry_port
  to_port                      = local.foundry_port
  referenced_security_group_id = data.aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "server_all" {
  security_group_id = aws_security_group.server.id
  description       = "Outbound for module downloads, S3, SSM (via fck-nat)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_instance" "server" {
  ami                                  = data.aws_ssm_parameter.al2023_ami_arm64.value
  instance_type                        = "t4g.medium"
  subnet_id                            = local.subnet_id
  vpc_security_group_ids               = [aws_security_group.server.id]
  iam_instance_profile                 = aws_iam_instance_profile.server.name
  instance_initiated_shutdown_behavior = "stop"

  # User-data edits apply in place (stop/start); use `terraform apply
  # -replace=aws_instance.server` to re-run first-boot provisioning. Data is
  # safe on EFS either way.
  user_data_replace_on_change = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    encrypted   = true
    volume_size = 16
    volume_type = "gp3"
  }

  user_data_base64 = base64gzip(templatefile("${path.module}/templates/user_data.sh.tpl", {
    efs_id             = aws_efs_file_system.data.id
    releases_bucket    = local.releases_bucket
    release_key        = local.release_key
    hostname           = local.hostname
    region             = "us-east-1"
    foundry_port       = local.foundry_port
    idle_stop_minutes  = local.idle_stop_minutes
    max_uptime_minutes = local.max_uptime_minutes
  }))

  tags = {
    Name = "${local.prefix}-server"
  }

  depends_on = [aws_efs_mount_target.data]
}
