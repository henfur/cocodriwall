# 09 — Testing & acceptance

## 1. Layers

| Layer | Tool | Runs in | Scope |
|-------|------|---------|-------|
| Module eval tests | `lib.evalModules` + expected failures | `nix flake check` | Every VAL-* check has a passing and a failing fixture |
| Compiler unit/snapshot | `cargo test`, `insta` snapshots | `nix flake check` | IR → nft/Suricata/dnsmasq output for `examples/*` |
| Evaluator property tests | `proptest` | `nix flake check` | Algebraic properties (shadowing, disjointness, priority order) |
| Conformance | NixOS VM test + packet generator | `nix flake check` (fast subset), nightly (full) | Kernel+Suricata verdicts == `ngfw-eval` verdicts |
| Integration (VM) | NixOS test framework, multi-node | `nix flake check` / nightly | End-to-end features (§2) |
| Telemetry | VM tests | nightly | Logs/metrics arrive with correct schema & attribution |
| Dashboards | VM test executing every panel query | nightly | DSH-007 |
| Visualizer | Unit tests + Playwright against built site | `nix flake check` | Views, filters, tracer results vs evaluator fixtures |
| Performance | Hardware lab (TRex / iperf3 / Suricata test pcaps) | per release | PERF-1..6 |

## 2. Required VM scenarios (topology: `client-lan`, `client-guest`, `fw`, `server-dmz`, `inet` (+ `monitor` for remote))

| ID | Scenario |
|----|----------|
| T-01 | Allow/deny/reject per zone pair; default deny logged with `_default-deny` |
| T-02 | IPv6 parity of T-01 |
| T-03 | Masquerade + port forward; port forward without allow is blocked and warned at build |
| T-04 | Established flows survive ruleset reload; `flushAffected` kills flows of a removed rule (P1) |
| T-05 | FQDN allow: access works after resolving via fw resolver, fails with direct IP before resolution; DNS redirect enforces resolver |
| T-06 | GeoIP deny using a test DB fixture mapping `inet` addresses to a country |
| T-07 | IPS drop with a custom test signature; alert-only signature in `detect` mode |
| T-08 | App deny (e.g. ssh over non-standard port detected as `ssh`) and app allow-list with `onUnknownApp` |
| T-09 | Suricata killed: inspected flows are dropped, non-inspected flows keep working, `NGFWIPSDown` fires; live rule reload causes no drops |
| T-10 | Commit-confirm: bad policy that blocks mgmt → automatic rollback within timeout; good policy confirmed |
| T-11 | Logs in Loki: decision/flow/ips records with correct `rule_id`, zones, NAT fields, community_id join |
| T-12 | Metrics: per-rule counters increase as expected; `ngfw_policy_info` matches built IR |
| T-13 | Grafana: provisioned dashboards present, UI save rejected, viewer role enforced, no listener outside mgmt; OIDC login via a test IdP (e.g. Dex/Kanidm in the VM); login form unavailable via nginx; break-glass admin login via loopback works and alerts |
| T-14 | Remote mode: telemetry over tunnel, buffered during monitor outage, delivered after |
| T-15 | Visualizer served behind auth; tracer verdicts for scenario packets equal observed verdicts |
| T-16 | *Withdrawn* (HA out of scope, D-15) |
| T-17..T-26 | DNS, DHCP & dynamic addressing scenarios, see 11 §7 |

## 3. Conformance

- TST-001 [P0] A generator samples flows from the IR's rule regions (boundary values of every
  address set, port range, zone pair, plus random points) and for app rules each catalog app
  plus `unknown`. For each sample the VM test sends real traffic and records the observed verdict
  (via counters and logs). Observed == `ngfw-eval` verdict and deciding rule ID, for 100% of
  samples.
- TST-002 [P0] The same samples are checked in the visualizer's WASM build (byte-identical
  evaluator ⇒ identical verdicts).

## 4. Definition of done (v1.0)

1. All P0 requirements implemented, each traced to at least one test (requirement ID in test name
   or annotation; a check reports untested P0 IDs).
2. All T-* scenarios marked P0 pass in CI.
3. PERF-1..6 measured on reference hardware and published; any miss has an accepted waiver.
4. `examples/branch-office` deploys on reference hardware and runs 7 days without alerts other
   than expected ones.
5. Docs: getting-started, option reference (generated from module options), log schema,
   metric reference, runbooks for every alert.
