# cocodriwall

> **WIP:** This project is at the specification stage. There is no implementation yet, and the
> specs may still change on any commit.

<p align="center">
  <img width=300 src="./assets/logo.png" />
</p>

A next-generation firewall for small offices and branch sites, built entirely on NixOS. The Git
repository is the firewall: every rule, object, feed version and dashboard is declared in Nix,
reviewed as a diff, built reproducibly, and deployed atomically with automatic rollback. There is
no management UI. You watch the firewall through Grafana and a read-only policy visualizer, and
you change it only through commits.

## Planned features

- **Zone-based stateful firewall** on nftables, IPv4 and IPv6, with NAT.
- **Inline IPS** with Suricata, **application identification**, and **FQDN and GeoIP rules**.
- **DNS and DHCP** for the site: local records from Nix, a caching validating resolver, per-zone
  DNS filtering, and DHCP with name registration.
- **Safe changes:** build-time validation, atomic apply, and commit-confirm with automatic
  rollback.
- **Every decision is named:** each allow or deny is attributable to a rule ID in logs, metrics
  and the visualizer.
- **Observability:** Prometheus, Loki and provisioned, read-only Grafana dashboards, on the
  firewall itself or on a separate monitor host.
- **Policy visualizer:** a static rules table, zone flow graph and "can A reach B?" path tracer.

## Specifications

The design lives in [docs/specs](docs/specs/README.md). Start with the
[overview](docs/specs/00-overview.md) for goals, non-goals and recorded decisions, then the
[policy model](docs/specs/02-policy-model.md), which describes the Nix configuration surface.

## Status

Specification draft. No implementation starts until the specs are approved.

## License

MIT, see [LICENSE](LICENSE).

## AI usage disclosure

Large language model tools (Claude, via Claude Code) were used to help develop this project,
including writing and refactoring code and documentation. I direct the design and review and test
the result, but parts of the code were generated.
