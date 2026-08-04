# foundry.ahara.io terminates TLS on the shared ALB (SNI cert below) and
# forwards straight to the instance. No auth action: Foundry brings its own
# admin-key/player-password auth, and WAF is bypassed for this host in
# ahara-infra (network/waf.tf, FoundryVttBypass rule).

# --- TLS certificate ---

resource "aws_acm_certificate" "this" {
  domain_name       = local.hostname
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id         = module.ctx.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.value]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_lb_listener_certificate" "this" {
  listener_arn    = module.ctx.alb.listener_arn
  certificate_arn = aws_acm_certificate_validation.this.certificate_arn
}

# --- Target group + rule ---

resource "aws_lb_target_group" "server" {
  name        = "${local.prefix}-tg"
  port        = local.foundry_port
  protocol    = "HTTP"
  vpc_id      = module.ctx.vpc.vpc_id
  target_type = "instance"

  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    path                = "/api/status"
    matcher             = "200"
  }

  tags = {
    Name = "${local.prefix}-tg"
  }
}

resource "aws_lb_target_group_attachment" "server" {
  target_group_arn = aws_lb_target_group.server.arn
  target_id        = aws_instance.server.id
  port             = local.foundry_port
}

resource "aws_lb_listener_rule" "server" {
  listener_arn = module.ctx.alb.listener_arn
  priority     = local.listener_rule_priority

  condition {
    host_header {
      values = [local.hostname]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.server.arn
  }
}

# --- DNS ---

resource "aws_route53_record" "server" {
  zone_id = module.ctx.route53_zone_id
  name    = local.hostname
  type    = "A"

  alias {
    name                   = module.ctx.alb.dns_name
    zone_id                = module.ctx.alb.zone_id
    evaluate_target_health = true
  }
}
