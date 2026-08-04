# foundry-vtt

Infrastructure and Discord wake-bot for a [Foundry Virtual Tabletop](https://foundryvtt.com/)
server at https://foundry.ahara.io, hosted on the ahara AWS platform. The
server stops itself between game sessions; steady-state cost is storage only.

## Quickstart

```bash
make ci            # clippy + fmt + tests + terraform fmt check
scripts/deploy.sh  # cargo lambda build + terraform apply (CI does this on main)
```

Day to day, the server is driven from Discord: `/foundry start|stop|status`.
First-time setup (license staging, Discord application, SSM parameters) is in
[docs/setup.md](docs/setup.md).

## Documentation

| Topic | Link |
| ---- | ---- |
| Architecture | [docs/architecture.md](docs/architecture.md) |
| First-time setup | [docs/setup.md](docs/setup.md) |
| Operations | [docs/operations.md](docs/operations.md) |
| Architecture decisions | [docs/adr/README.md](docs/adr/README.md) |
| Backlog | [docs/backlog.md](docs/backlog.md) |
| Changelog | [CHANGELOG.md](CHANGELOG.md) |
| Agent guide | [AGENTS.md](AGENTS.md) |

## License

MIT — see [LICENSE](LICENSE). Foundry VTT itself is commercial software
licensed separately by its publisher.
