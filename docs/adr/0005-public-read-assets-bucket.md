# 0005 — Public-read assets bucket

- Status: Accepted
- Date: 2026-08-04

## Context

Foundry's native S3 media integration generates direct S3 object URLs for
player browsers and attaches a `public-read` ACL to every upload. The ahara
platform otherwise serves all public content through CloudFront with Origin
Access Control and keeps every bucket fully blocked.

## Decision

Make `foundry-vtt-assets-<account id>` publicly readable: public-GetObject
bucket policy, `BucketOwnerPreferred` object ownership, ACL blocks disabled,
CORS for the foundry origin. The instance role carries `s3:PutObjectAcl` so
Foundry's ACL-bearing uploads succeed. A dedicated `s3-bucket-policy`
deployer policy primitive exists in ahara-infra so this capability is granted
per-project rather than platform-wide.

## Alternatives considered

- **CloudFront + OAC (platform posture)** — keeps the bucket private, but
  Foundry generates S3 URLs itself and has no CDN-domain rewrite; the
  integration simply would not serve assets.
- **No S3 integration; media on EFS** — works, at ~13× the storage cost and
  with all media traffic proxied through the game instance.

## Consequences

The bucket holds only game media (maps, tokens, audio) — never player data —
and that boundary is the operating rule for what gets uploaded. Object URLs
are world-readable to anyone who has them. Asset serving bypasses the
instance entirely, keeping the EFS data set and session bandwidth small.
