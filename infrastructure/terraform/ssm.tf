# Foundry's server administrator password (the setup-screen admin key).
# Generated here and published to SSM; Foundry itself only stores a hash, so
# this parameter is the retrievable source of truth. Enter it once in the
# Foundry setup UI (README, first boot):
#   aws ssm get-parameter --name /ahara/foundry-vtt/admin-password \
#     --with-decryption --query Parameter.Value --output text

resource "random_password" "foundry_admin" {
  length           = 32
  special          = true
  override_special = "!@#$%^&*"
}

resource "aws_ssm_parameter" "foundry_admin_password" {
  name  = "${local.ssm_prefix}/admin-password"
  type  = "SecureString"
  value = random_password.foundry_admin.result
}
