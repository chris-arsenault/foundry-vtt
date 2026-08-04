module "ctx" {
  source = "git::https://github.com/chris-arsenault/ahara-tf-patterns.git//modules/platform-context"
}

# The shared ALB security group is not exported by platform-context; discover
# it by tag so the server SG can scope ingress to ALB traffic only.
data "aws_security_group" "alb" {
  filter {
    name   = "tag:sg:role"
    values = ["alb"]
  }
  filter {
    name   = "tag:sg:scope"
    values = ["public"]
  }
}
