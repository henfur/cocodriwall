# 10 — Roadmap & open questions

## Milestones

| M | Name | Contents | Exit criteria |
|---|------|----------|---------------|
| M0 | Foundations | Flake skeleton, feed mirror repo + bot (needed by M2/M3, cheap to start early), IR types + JSON schema, module options for zones/objects/services/rules/NAT, eval validation, `ngfw-compile` for L3/L4 + NAT, `nft -c` check | T-01..03 pass |
| M1 | Operable L4 firewall | Commit-confirm/rollback, exporter, ulogd2 + Vector + Loki + Prometheus + Grafana (local mode), D1/D3/D4/D5/D8 | T-04, T-10..13 pass |
| M2 | DNS & DHCP | **Spike first (DNS-037)**; dnsmasq instances + Unbound, local records, DNSSEC, per-zone filter profiles + blocklist feeds, DHCP v4/v6 with name registration, reservations as objects, WAN DHCP + IPv6 prefix delegation (`ngfw-prefixd`), D9 | T-17..22, T-24..26 |
| M3 | NGFW | **Spike first (DP-044)**; Suricata IPS, App-ID, FQDN rules, GeoIP, D6/D7 | T-05..09, T-23 + conformance incl. apps |
| M4 | Visualizer | Rules table, zone matrix, flow graph, path tracer (WASM), Grafana cross-links | T-15, VIZ P0 |
| M5 | Remote monitoring | `ngfw-monitor` module, tunnel, buffering, multi-firewall | T-14 |
| M6 | Hardening & release | Perf lab, security review, docs, example site 7-day soak | DoD (09 §4) |
| — | v1.x | Policy diff + CI comments, live counters in viz, per-rule IDS, nDPI, rate limits, synproxy, host-name enrichment of flow logs, signed commits | |

## Open questions

| ID | Question | Recommendation | Ref |
|----|----------|----------------|-----|
| OPEN-2 | App-ID catalog: Suricata-native + SNI only, or nDPI in v1? | Suricata-native for v1, nDPI P1 | 02 §5 |
| OPEN-4 | NIC model(s) for the reference hardware (CPU/RAM decided: D-9) — determines 2.5 vs 10 GbE targets and hardware offload | Intel I226 (2.5 GbE) or X710/E810 (10 GbE) | 03 §4 |
| OPEN-5 | Vector vs Grafana Alloy for log pipeline? | Vector (VRL, enrichment, disk buffers) | 04 |
| OPEN-6 | Remote telemetry transport: module-managed WireGuard vs mTLS? | WireGuard (simpler, covers both scrape and push) | 01 §3.2 |
| OPEN-7 | Mechanism for per-rule `inspect = "ids"` | Defer to P1; decide after M3 spike | 03 §5 |
| OPEN-11 | Should `deny` logs for WAN-ingress noise (scans) be sampled by default to protect log volume? | Yes: `_default-deny` from `wan` sampled 1/10 by default | 04 §3 |
| OPEN-12 | Grafana-native view of policy in addition to the visualizer (e.g. rule table panel from `ngfw_rule_info`)? | Yes, cheap: a "Rules" table panel in D3 | 05 |
| OPEN-13 | Project name / module namespace | — | README |
| OPEN-14 | Licensing of this project, and whether ET Open / DB-IP terms permit a *public* feed mirror (a private per-site mirror is assumed fine; to verify) | — | 03 §8, 07 §5.1 |

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
