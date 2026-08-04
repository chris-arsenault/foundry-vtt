# 0003 — Wake bot behind the shared ALB

- Status: Accepted
- Date: 2026-08-04

## Context

Discord interaction webhooks need a public HTTPS endpoint that can
start/stop the game server. The platform forbids API Gateway and routes all
HTTP backends through the shared ALB via the alb-api module (Rust
`lambda_http`). An initial implementation used a Node.js Lambda with a
Function URL.

## Decision

Implement the wake bot as a Rust `lambda_http` Lambda (manual routing, no
Axum) behind the shared ALB at `api.foundry-vtt.ahara.io` via the stock
alb-api module, listener priority 231, unauthenticated route.

## Alternatives considered

- **Lambda Function URL (initial implementation)** — fewest resources and no
  listener priority to claim, but a second endpoint pattern the platform
  otherwise never uses: no ALB access logs, no WAF, an unstable-looking URL,
  and a divergent Node.js runtime. Rejected because pattern drift costs more
  than the marginal AWS resources; the platform's single API shape wins.
- **API Gateway** — prohibited by platform constraint.

## Consequences

The wake endpoint gets ALB access logging, WAF, a stable hostname, and the
same deploy pipeline as every other platform API. The repo gains a `rust`
stack (clippy/fmt/test in CI, `cargo lambda build`). The Discord app's
Interactions Endpoint URL is `https://api.foundry-vtt.ahara.io/` and never
changes with redeploys.
