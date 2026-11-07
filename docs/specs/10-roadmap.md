# 10 — Roadmap & open questions

## Milestones

| M | Name | Contents | Exit criteria |
|---|------|----------|---------------|
| M0 | Foundations | Flake skeleton, feed mirror repo + bot (needed by M2/M3, cheap to start early), IR types + JSON schema, module options for zones/objects/services/rules/NAT, eval validation, `cdw-compile` for L3/L4 + NAT, `nft -c` check | T-01..03 pass |
| M1 | Operable L4 firewall | Commit-confirm/rollback, exporter, ulogd2 + Vector + Loki + Prometheus + Grafana (local mode), D1/D3/D4/D5/D8 | T-04, T-10..13 pass |
| M2 | DNS & DHCP | **Spike first (DNS-037)**; dnsmasq instances + Unbound, local records, DNSSEC, per-zone filter profiles + blocklist feeds, DHCP v4/v6 with name registration, reservations as objects, WAN DHCP + IPv6 prefix delegation (`cdw-prefixd`), D9 | T-17..22, T-24..26 |
| M3 | NGFW | **Spike first (DP-044)**, whose outcome also selects the DP-036 mechanism (D-21); Suricata IPS, App-ID, FQDN rules, GeoIP, D6/D7 | T-05..09, T-23 + conformance incl. apps |
| M4 | Visualizer | Rules table, zone matrix, flow graph, path tracer (WASM), Grafana cross-links | T-15, VIZ P0 |
| M5 | Remote monitoring | `cdw-monitor` module, tunnel, buffering, multi-firewall | T-14 |
| M6 | Hardening & release | Perf lab, security review, docs, example site 7-day soak | DoD (09 §4) |
| — | v1.x | Policy diff + CI comments, live counters in viz, per-rule IDS, nDPI extended app catalog (POL-035), rate limits, synproxy, host-name enrichment of flow logs, signed commits | |

## Open questions

None. New questions get the next free ID (OPEN-20).

### Resolved

| ID | Resolution | Decision |
|----|------------|----------|
| OPEN-1 | Rust | D-6 |
| OPEN-4 (partial) | x86-64, 4 cores, 8 GB RAM | D-9 |
| OPEN-8 | IPS fails closed | D-10 |
| OPEN-10 | OIDC only | D-11 |
| OPEN-3 | Append-only feed mirror repo | D-12 |
| OPEN-9 | Superseded by 11 §1 | D-14 |
| OPEN-15 | dnsmasq front + Unbound backend | D-14 |
| OPEN-16 | Per-zone filter profiles mandatory (P0) | D-16 |
| OPEN-17 | Moot: HA out of scope | D-15 |
| OPEN-18 | Prefix delegation in v1 (P0) | D-17 |
| OPEN-19 | No blocklist on by default; catalog contents chosen in M2 after license checks | D-18 |
| OPEN-2 | Suricata-native catalog for v1; nDPI extended catalog later (P1) | D-19 |
| OPEN-5 | Vector | D-7 |
| OPEN-6 | Plain HTTP + Loki auth/mTLS options; encryption left to the infrastructure | D-20 |
| OPEN-7 | Deferred to P1; mechanism chosen after the M3 spike | D-21 |
| OPEN-11 | `_default-deny` from WAN zones sampled 1/10 by default | D-22 |
| OPEN-12 | Rules table panel in D3 | D-23 |
| OPEN-13 | cocodriwall, prefix `cdw` | D-24 |
| OPEN-4 | Intel I226 2.5 GbE baseline; optional 10 GbE profile | D-25 |
| OPEN-14 | MIT; no public mirror, self-hosted mirror only | D-26 |
