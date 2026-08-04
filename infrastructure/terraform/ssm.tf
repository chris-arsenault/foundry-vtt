# Foundry's server administrator password (the setup-screen admin key).
# User-owned: set your own value here and enter the same one in the Foundry
# setup UI. Terraform never generates it — generated secrets end up readable
# in Terraform state.
#   aws ssm put-parameter --name /ahara/foundry-vtt/admin-password \
#     --type SecureString --value <admin password> --overwrite

resource "aws_ssm_parameter" "foundry_admin_password" {
  name  = "${local.ssm_prefix}/admin-password"
  type  = "SecureString"
  value = "PENDING"

  lifecycle {
    ignore_changes = [value]
  }
}
