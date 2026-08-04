# 0004 — Guild allowlist authorization for the wake bot

- Status: Accepted
- Date: 2026-08-04

## Context

Discord signs every interaction with the application's ed25519 key, which
proves a request came from Discord *for this application* — not that it came
from our server. Discord application IDs are not secrets, and anyone who gets
the app installed into their own guild produces validly signed interactions.
The platform's standard ALB auth (`jwt-validation` against Cognito) cannot
apply: Discord's servers are the caller and cannot present Cognito tokens.

## Decision

Authorize in the handler: reject any command interaction whose `guild_id`
differs from the SSM parameter `/ahara/foundry-vtt/discord-guild-id`
(exact-compare, so the `PENDING` placeholder fails closed). Register the
slash command guild-scoped so it does not exist elsewhere, and keep the
Discord app's Public Bot toggle off.

## Alternatives considered

- **Signature verification only** — treats "from Discord" as "from us";
  anyone installing the app elsewhere could start/stop the instance.
- **User-ID allowlist** — finer-grained but duplicates what Discord's own
  server-side command permissions already do per-role/channel within the
  home guild; guild granularity plus in-server permission config covers it.
- **ALB `jwt-validation`** — the platform norm, but structurally impossible
  for Discord webhooks.

## Consequences

The worst case for a leaked application ID is a rejected command and a
warning log line. Per-user restriction inside the home server is delegated to
Discord's Integrations permission UI. Adding a second server means changing
the single-value parameter to a list — a deliberate code change.
