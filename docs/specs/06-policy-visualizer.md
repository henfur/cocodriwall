# 06 — Policy visualizer

A static, read-only single-page app built by Nix from the IR. It cannot change anything: it has
no backend, makes no write requests, and any "edit" is done in Git.

## 1. Inputs

| File | Origin | Content |
|------|--------|---------|
| `policy.json` | IR (02 §10) | Zones, objects, services, apps, rules, NAT, system rules, source locations |
| `rule-map.json` | `ngfw-compile` | Rule ID ↔ tag ↔ SID range |
| `analysis.json` | `ngfw-compile` | Shadowed/redundant/broad findings, port-forward coverage |
| `routes.json` | module | Connected networks + static routes per zone (§4.3) |
| `geo/*.bin` | `ngfw-compile` | Compact prefix sets for referenced countries only (for the tracer) |
| `ngfw_eval.wasm` | `crates/ngfw-eval` | Evaluator (principle 2) |
| `live/<firewall>.json` | runtime, optional [P1] | Per-rule hit counts & last-hit (§5) |

- VIZ-001 [P0] The site is a Nix derivation (`packages.visualizer` + data) with no network
  access at runtime other than fetching its own files. No CDN, no telemetry, strict CSP
  (`default-src 'self'; script-src 'self' 'wasm-unsafe-eval'`).
- VIZ-002 [P0] In `remote` mode the monitor host builds one site with a firewall selector;
  each firewall's data lives under `data/<firewall>/`.
- VIZ-003 [P0] The header always shows: site, `policy_hash`, git rev, build time, IR schema
  version. A banner warns if the deployed generation (from `live/*.json` or the exporter) differs
  from the bundled one.

## 2. Views

### 2.1 Rules table (default view)
Columns: priority, ID, enabled, from → to, source, destination, services, apps, action,
inspect, log, owner/ticket/tags, expires, analysis badges, hits & last hit [P1], source
location (`file:line`, linking to the Git host if `ui.repoUrl` is set).

- VIZ-010 [P0] Rules are shown in **evaluation order**; system rules shown and visually
  distinct, hideable by toggle.
- VIZ-011 [P0] Filters: free text, zone (from/to/either), object (matches rules referencing it
  **directly or via groups**), IP address (matches rules whose resolved sets contain it),
  service/port, app, action, inspect, owner, tag, analysis finding, enabled.
- VIZ-012 [P0] Group-by: zone pair (collapsible sections), owner, action.
- VIZ-013 [P0] Expanding a row shows the fully resolved rule: every object expanded to its
  addresses (with the group path it came from), every service to proto/ports, every app to its
  detection predicates, the generated nft rule text and Suricata rules (from build artifacts),
  and analysis notes ("shadowed by `users-web-out` (priority 1000)").
- VIZ-014 [P0] Every rule, object, zone has a permalink (`#/rules/<id>`); URL encodes all
  filter state.
- VIZ-015 [P0] Handles 5 000 rules / 2 000 objects with < 100 ms filter latency (virtualized table).

### 2.2 Zone matrix
A `from × to` grid (including `self`). Each cell summarizes the pair: number of allow / deny
rules, whether anything is allowed at all, whether inspection applies, whether `any`-rules
contribute; colored by posture (closed / restricted / broad). Click → table filtered to that pair.

### 2.3 Flow graph
```
   [wan] ──(https, ips)──▶ [dmz: web1]
     ▲                         │
     │ allow http/https (ips)  │ allow https,ssh → fqdn:github
   [lan: users] ───────────────┘
     │  ✕ deny app:bittorrent
     ▼
   [self] (mgmt only)
```
- VIZ-020 [P0] Nodes are zones (compound nodes); toggling a zone "expanded" reveals the objects
  referenced in rules as child nodes. External objects (FQDN, geo, internet CIDRs) are shown as
  nodes inside the zone they route to (§4.3).
- VIZ-021 [P0] Edges aggregate rules by `(from, to, action)` with labels summarizing services /
  apps; color encodes action (allow / deny / inspect), dashed = disabled or app-eventual.
  Clicking an edge lists its rules in a side panel.
- VIZ-022 [P0] Layout is deterministic (same IR ⇒ same picture). Optional layout hints
  `zones.<z>.ui = { column; row; }` in Nix; default layered layout with WAN on the left,
  `self` at the bottom.
- VIZ-023 [P1] Edge thickness by hit rate from `live/*.json`; rules with zero hits rendered faded.
- VIZ-024 [P0] Rendering library: Cytoscape.js (with an elk/dagre layout), bundled.

### 2.4 Path tracer ("can A reach B?")
Inputs: source (IP, object, or zone), destination (IP, object, FQDN, or country),
protocol + port, optional app, optional ingress interface override.

Output:
1. **Verdict** (allow / deny / reject / allow-then-inspect / depends-on-app) and the deciding rule.
2. **Trace**: zone resolution (which interface/zone each side maps to and why), DNAT applied,
   then each rule considered in order with the reason it did not match ("source 10.10.0.5 ∉
   o_dmz_hosts"), the match, and SNAT applied.
3. Highlighted path on the flow graph.

- VIZ-030 [P0] The tracer calls `ngfw_eval.wasm`; it MUST NOT reimplement matching in TypeScript.
- VIZ-031 [P0] If the destination is a FQDN, the tracer evaluates against FQDN *objects*
  (does the name fall under `fqdn:github`?) and explains that runtime resolution decides the
  actual IP match. If the destination is an IP, FQDN-based rules are reported as
  "matches only if the IP was recently resolved for one of: …".
- VIZ-032 [P0] If the app is unspecified and the deciding point depends on an app, the tracer
  returns `depends-on-app` with the per-app outcome table (each candidate app and `unknown`).
- VIZ-033 [P1] "Reachability from zone" mode: for a source zone, list every destination
  zone/object/service that is reachable (computed by the evaluator over the rule regions).

### 2.5 Objects, services, apps
Lists with "where used" (rules referencing directly or transitively), unused objects flagged.

### 2.6 Analysis
List of all `analysis.json` findings with severity and links (shadowed, redundant, broad,
uncovered port forwards, equal-priority overlaps, expiring rules).

## 3. Diff (P1)
- VIZ-040 [P1] `nix run .#policy-diff -- <rev-a> <rev-b>` evaluates both revisions' IRs and
  produces (a) Markdown for PR comments (rules added/removed/changed, effective-reachability
  changes per zone pair) and (b) a static diff page using the visualizer components.
- VIZ-041 [P1] CI posts the Markdown diff on every PR touching policy.

## 4. Data requirements on the IR

- 4.1 POL-081 source locations and original references (not just resolved values) are needed
  for VIZ-013.
- 4.2 Analysis findings are referenced by rule ID.
- 4.3 **Routing snapshot**: to tell which zone a destination IP is in, the module exports
  connected networks (from `networking.interfaces.*.ipv{4,6}.addresses`, VLAN/bridge/WireGuard
  config) and static routes, mapped to zones. The default route's zone is the "internet" zone.
  Dynamic routes are not modelled; the tracer shows the assumption it used.

## 5. Live data (P1)

- VIZ-050 [P1] A systemd timer on the monitor host queries Prometheus every 60 s for
  `ngfw_rule_hits_total` rates and `ngfw_rule_last_hit_timestamp_seconds` and writes
  `live/<firewall>.json`. The SPA polls it. No API proxy is exposed to the browser.

## 6. Hosting and integration

- VIZ-060 [P0] Served by nginx at `/viz/` on the same origin as Grafana (`/grafana/`),
  behind the same authentication (08 §3).
- VIZ-061 [P0] Grafana links: a dashboard link "Policy" on every dashboard to `/viz/`;
  the visualizer links rules to `D4 Rule detail` with `var-rule=<id>&var-firewall=<fw>`.
- VIZ-062 [P0] Usable at ≥ 1280 px wide; readable (read-only table) on mobile;
  light/dark themes; keyboard-navigable; colors not the only carrier of meaning (icons
  for allow/deny).
