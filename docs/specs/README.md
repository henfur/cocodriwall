# NixNGFW — Specifications

> Status: **DRAFT v0.4** (2026-10-13). No implementation starts until these are approved.
> Working name "NixNGFW" and the module namespace `services.ngfw` are placeholders.

## Documents

| # | Document | Scope |
|---|----------|-------|
| 00 | [Overview](00-overview.md) | Vision, goals, non-goals, principles, recorded decisions, glossary |
| 01 | [Architecture](01-architecture.md) | Components, topologies (local / remote monitoring), data flows, repo layout |
| 02 | [Policy model](02-policy-model.md) | The Nix configuration surface: zones, objects, services, rules, NAT, validation |
| 03 | [Data plane](03-dataplane.md) | nftables layout, conntrack, offload, IPS (Suricata/NFQUEUE), App-ID, FQDN, GeoIP |
| 04 | [Observability](04-observability.md) | Metrics, logs, log schema, pipeline, retention, cardinality |
| 05 | [Dashboards](05-dashboards.md) | Grafana provisioning and every dashboard/panel |
| 06 | [Policy visualizer](06-policy-visualizer.md) | Static, read-only rules UI: table, flow graph, path tracer |
| 07 | [Operations](07-operations.md) | Deployment, safe apply / auto-rollback, feeds, secrets, upgrades |
| 08 | [Security](08-security.md) | Threat model, management plane hardening, access control |
| 09 | [Testing & acceptance](09-testing.md) | Test strategy, conformance, performance, definition of done |
| 10 | [Roadmap & open questions](10-roadmap.md) | Milestones, consolidated open questions |
| 11 | [DNS & DHCP](11-dns-dhcp.md) | Local DNS records, caching/validating resolver, DNS filtering, DHCP with name registration |

## Conventions

- **MUST / SHOULD / MAY** follow RFC 2119.
- Requirements carry stable IDs (`POL-012`, `DP-030`, …). IDs are never reused; removed
  requirements are marked *Withdrawn*.
- Priority tags: **[P0]** required for v1.0, **[P1]** v1.x, **[P2]** later / nice to have.
- `> OPEN:` blocks mark unresolved questions; all are also listed in [10-roadmap](10-roadmap.md#open-questions).
