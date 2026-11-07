# 00 — Overview

## 1. Vision

A next-generation firewall for SMB / branch sites built entirely on NixOS. **The Git
repository is the firewall.** Every rule, object, feed version, dashboard and user is declared
in Nix, reviewed as a diff, built reproducibly, and deployed atomically with automatic
rollback. There is no management UI. Humans *observe* through Grafana and a read-only
policy visualizer; they *change* things only through commits.

## 2. Goals

| ID | Goal |
|----|------|
| G-1 | Stateful, zone-based L3/L4 firewall (IPv4 + IPv6, NAT) on nftables. |
| G-2 | "Next-gen" capabilities: inline IDS/IPS, application identification, FQDN-based rules, GeoIP rules. |
| G-3 | 100% declarative: the running state is a pure function of the flake + pinned inputs (+ secrets). The only runtime state is DHCP leases, dynamically registered names, delegated IPv6 prefixes and DHCP-learned WAN addresses, FQDN set contents and the DNS cache, and none of it can widen what the policy allows (DHCP-022). |
| G-4 | Grafana dashboards for traffic metrics, traffic (flow) logs, allow/deny decisions, IPS events, system health. |
| G-5 | A read-only policy visualizer: rules table, zone flow graph, and "can A reach B?" path tracer. |
| G-6 | Monitoring stack co-located on the firewall **or** on a separate monitor host, selected by one option. |
| G-7 | Safe change management: build-time validation, atomic apply, commit-confirm with automatic rollback. |
| G-8 | Every allow/deny decision is attributable to a named rule, in logs, metrics and the visualizer. |
| G-9 | The firewall is the site's DNS and DHCP server: local records from Nix, caching validating resolver, DNS filtering, DHCP with name registration (11). |

## 3. Non-goals (v1)

| ID | Non-goal | Rationale |
|----|----------|-----------|
| NG-1 | Any write path from a UI (Grafana, visualizer, API). | Core principle. |
| NG-2 | TLS interception / decrypt-and-inspect. | Complexity, privacy, CA distribution. App-ID uses SNI/JA3/JA4 and DNS instead. |
| NG-3 | Dynamic routing (BGP/OSPF), SD-WAN, policy-based routing. | Out of scope; can be layered with existing NixOS modules. |
| NG-4 | User-identity rules (AD/LDAP user → IP mapping). | Revisit post-v1. |
| NG-5 | Captive portal, web proxy, AV scanning. | Not firewall core. (DHCP moved into scope, D-13.) |
| NG-6 | Multi-tenant / multi-admin RBAC on config. | Git hosting provides review/ownership (CODEOWNERS). |
| NG-7 | Non-NixOS targets. | — |
| NG-8 | High availability (active/passive pairs, state sync). | Out of scope for now (D-15). |

VPN (WireGuard) is **not** a feature of this project, but WireGuard interfaces configured with
stock NixOS options MUST be assignable to zones like any other interface.

## 4. Design principles

1. **Single source of truth → single IR.** The Nix module evaluates the user's policy into one
   canonical intermediate representation (`policy.json`). Every artifact (nftables ruleset,
   Suricata rules, resolver config, dashboards variables, visualizer data) is generated from
   that IR, never from the raw Nix options directly.
2. **One evaluator.** Rule-matching semantics are implemented once (compiler crate) and reused
   by the visualizer's path tracer (compiled to WASM) and by conformance tests. The visualizer
   can therefore never "lie" about what the data plane does.
3. **Fail at build time.** Anything detectable at evaluation/build time (dangling references,
   invalid ruleset, rule-ID collision, shadowed rules in strict mode) MUST fail the build, not
   the deploy.
4. **Every decision is named.** Every rule has a stable, human-readable ID that appears in
   counters, logs, alerts and the UI. Implicit behavior (default deny, auto-generated
   management rules) also gets reserved IDs.
5. **Observability is not optional.** The firewall without its telemetry is a supported
   configuration, but telemetry is on by default and its loss is itself alerted.
6. **Boring components.** nftables, Suricata, dnsmasq, Unbound, ulogd2, Vector, Prometheus, Loki,
   Grafana, nginx — all already packaged in nixpkgs. Custom code is limited to the
   compiler/IR tooling, one exporter, and the visualizer.

## 5. Recorded decisions

| ID | Decision | Date | Notes |
|----|----------|------|-------|
| D-1 | v1 NGFW scope = IDS/IPS (Suricata) + App-ID + FQDN & GeoIP rules. TLS inspection excluded. | 2026-10-13 | User decision |
| D-2 | Monitoring topology: both co-located and remote monitor host supported. | 2026-10-13 | User decision |
| D-3 | Rules visualization = static read-only site built by Nix, linked from Grafana. | 2026-10-13 | User decision |
| D-4 | Target: SMB/branch, 1–10 Gbps, many VLANs. (HA: see D-15.) | 2026-10-13 | User decision |
| D-5 | Rules are an attribute set keyed by ID with explicit numeric `priority`, not an ordered list. | proposed | Nix list merge order across modules is not a sane ordering mechanism. See 02 §6. |
| D-6 | Compiler / analyzer / evaluator written in Rust; evaluator compiled to WASM for the visualizer. | 2026-10-13 | User decision (was OPEN-1). See 01 §4. |
| D-7 | Log pipeline uses Vector (not Alloy/Promtail). | proposed | VRL transforms + GeoIP enrichment + disk buffers. OPEN-5. |
| D-8 | Threat/Geo feeds pinned as flake inputs by default; runtime refresh is opt-in. | proposed | Preserves G-3. |
| D-13 | DNS & DHCP in scope: local records from Nix, caching resolver, DNS filtering, DHCP with automatic name registration. Split-horizon views not in scope. | 2026-10-13 | User decision. See 11. |
| D-14 | DNS architecture: dnsmasq front (DNS instances per filter profile + one DHCP instance) with a loopback-only Unbound backend. | 2026-10-15 | User decision (was OPEN-15). See 11 §1. |
| D-15 | HA is out of scope for now. | 2026-10-15 | User decision. Withdraws OPS-060..062 and T-16; makes OPEN-17 moot. |
| D-16 | Per-zone DNS filter profiles are mandatory in v1 (P0). | 2026-10-15 | User decision (was OPEN-16). See 11 §2.3–2.4. |
| D-17 | DHCPv6 prefix delegation and DHCP-learned WAN addresses are in v1 (P0). | 2026-10-15 | User decision (was OPEN-18). See 11 §3.4. |
| D-18 | No DNS blocklist is enabled by default. | 2026-10-15 | User decision (was OPEN-19). |
| D-12 | Feeds are delivered through an append-only feed mirror Git repo, pinned by commit; no binary cache required. | 2026-10-13 | User decision (was OPEN-3). See 07 §5. |
| D-9 | Reference hardware: x86-64, 4 CPU cores, 8 GB RAM. | 2026-10-13 | User decision (was OPEN-4). NIC model still TBD. Implies IPS inspection is **selective** (only `inspect = "ips"` / app rules), not line-rate for all traffic. |
| D-10 | IPS fails **closed**: traffic selected for inspection is blocked when Suricata is unavailable. | 2026-10-13 | User decision (was OPEN-8). Non-inspected traffic is unaffected. |
| D-11 | Authentication to Grafana and the visualizer is OIDC only; no local user accounts. | 2026-10-13 | User decision (was OPEN-10). Break-glass access: 08 §4. |

## 6. Glossary

| Term | Meaning |
|------|---------|
| **Zone** | Named set of interfaces sharing a trust level. Policy is written between zones. |
| **`self` zone** | Reserved zone for traffic to/from the firewall host itself. |
| **Object** | Named address entity: host, network, range, group, FQDN set, geo set. |
| **Service** | Named L4 protocol/port set (e.g. `https` = tcp/443 + udp/443). |
| **App** | Named L7 application signature (e.g. `ssh`, `bittorrent`, `youtube`), detected by Suricata. |
| **Rule** | Match (zones, objects, services, apps) + action (`allow`, `deny`, `reject`) + options (inspect, log). |
| **IR** | Intermediate representation: canonical, validated, fully-resolved JSON policy. |
| **Generation** | One NixOS system generation; each has exactly one IR, identified by `policy_hash`. |
| **Inspect** | Rule option sending matched traffic through Suricata (`ids` = mirror/alert, `ips` = inline). |
| **Monitor host** | Host running Prometheus/Loki/Grafana/visualizer — the firewall itself or a separate machine. |
