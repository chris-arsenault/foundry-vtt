# Foundry's data directory (worlds, modules, config) lives on EFS so the
# instance itself is disposable: upgrades replace the instance, data persists.

resource "aws_security_group" "efs" {
  name        = "${local.prefix}-efs-sg"
  description = "NFS access to the Foundry data filesystem"
  vpc_id      = module.ctx.vpc.vpc_id

  tags = {
    Name = "${local.prefix}-efs-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_server" {
  security_group_id            = aws_security_group.efs.id
  description                  = "NFS from the Foundry server"
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  referenced_security_group_id = aws_security_group.server.id
}

resource "aws_efs_file_system" "data" {
  creation_token = "${local.prefix}-data"
  encrypted      = true

  # Worlds and modules are mostly cold between sessions.
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = {
    Name = "${local.prefix}-data"
  }
}

resource "aws_efs_mount_target" "data" {
  file_system_id  = aws_efs_file_system.data.id
  subnet_id       = local.subnet_id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_backup_policy" "data" {
  file_system_id = aws_efs_file_system.data.id

  backup_policy {
    status = "ENABLED"
  }
}
