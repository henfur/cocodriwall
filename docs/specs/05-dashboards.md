# 05 — Grafana & dashboards

## 1. Provisioning

- DSH-001 [P0] Grafana is configured entirely by the NixOS module: datasources (Prometheus,
  Loki, with fixed UIDs `cdw-prom`, `cdw-loki`), dashboards, folders, alert rules, contact
  points, notification policies, users/teams (or OIDC role mapping).
- DSH-002 [P0] Dashboard provider: `allowUiUpdates = false`, `disableDeletion = true`; every
  dashboard JSON has `editable = false`. UI changes cannot be saved.
- DSH-003 [P0] Dashboards are authored in Jsonnet + Grafonnet under `dashboards/`, compiled in a
  derivation, and pinned to the Grafana version in nixpkgs. Raw JSON exports are not accepted
  in review (diffs unreadable).
- DSH-004 [P0] Build-time templating from the IR: the zone list, rule list and firewall list are
  injected as `custom` variables, so dropdowns are correct even before data exists.
- DSH-005 [P0] Every dashboard has the variables `firewall`, `from_zone`, `to_zone`, and the
  annotation source "Policy changes" (Loki `stream="change"`), so every graph shows when
  policy changed.
- DSH-006 [P0] Cross-links: every panel showing a `rule_id` has a data link to the
  **Rule detail** dashboard and to the visualizer (`/viz/#/rules/<id>`); the visualizer links
  back (06 §6).
- DSH-007 [P0] A VM test (09) loads every dashboard and executes every panel query against a
  populated Prometheus/Loki, failing on query errors or "no data" for panels marked
  `required`.

## 2. Dashboards

### D1 — Overview (home dashboard)
- Stat row: throughput in/out (WAN), new flows/s, active flows / conntrack max (%), denies/s,
  IPS alerts (24 h) by severity, policy generation + `policy_hash` + age, feed ages,
  pipeline health (green/red).
- Time series: per-zone throughput (node_exporter, interfaces mapped to zones from the IR).
- Time series: allows vs denies per second (stacked).
- Table: top 10 deny rules (24 h), top 10 IPS signatures (24 h).
- Annotations: policy changes, rollbacks.

### D2 — Traffic
- Zone-pair matrix (heatmap-style table) of bytes/s from `cdw:zone_pair_bytes:rate5m`.
- Throughput, pps, errors/drops per interface.
- Top talkers (src IP), top destinations (dst IP / FQDN / SNI), top destination countries
  (geomap panel), top apps — all LogQL `topk` over `stream="flow"`.
- Flow duration and size distribution (histograms).
- NAT: top port-forward hits, SNAT pool usage [P1].

### D3 — Policy decisions
- Allows vs denies over time, by zone pair.
- Per-rule hit rate (top N), **filterable by action**.
- "Unused rules": rules with `cdw_rule_last_hit_timestamp_seconds` older than `$unused_days`
  (default 30) or never hit, joined with `cdw_rule_info` (owner, expires).
- Rules expiring within 30 days (from `cdw_rule_info{expires}`).
- Deny log table (live tail): ts, rule_id, zones, src → dst:port, proto, geo; click-through to
  flow explorer filtered by src/dst.
- `_default-deny` hits by zone pair (signals missing rules), from counters (exact), not from the
  sampled WAN deny logs (POL-045).
- Rules table (D-23): every rule from `cdw_rule_info` (priority, ID, action, inspect, owner,
  enabled, expires, system) joined with hit rate and last hit, sortable and filterable. Each row
  links to D4 and to the visualizer. It complements the visualizer for quick checks inside
  Grafana; resolved objects, the flow graph and the path tracer stay in the visualizer.

### D4 — Rule detail (variable `rule`)
- Rule metadata panel (from `cdw_rule_info` + link to visualizer, showing description/owner/ticket).
- Hits/s, last hit, cumulative hits since generation.
- Bytes attributed (from flow logs), top sources, top destinations, top apps for this rule.
- Recent matching log lines.

### D5 — Flow log explorer
- Logs panel + table over `stream=~"flow|decision"` with ad-hoc filters for src/dst IP, port,
  app, rule, action, geo, FQDN; `community_id` link opens all related events (flow + app + ips).

### D6 — Threats (IPS)
- Alerts and drops over time by severity; top signatures; top attacking sources (with geo);
  top targeted internal hosts; signature classtype breakdown.
- Table of recent alerts with signature message, action taken (alert/drop), rule_id
  (firewall rule that sent the flow to inspection).
- Suricata health: kernel/queue drops, capture rate, memcap hits.

### D7 — Applications
- Top apps by bytes and flows; app-denies by rule; unknown-app rate.
- Blocked DoT/DoH attempts (`_dot-block`, `_doh-block`).

### D9 — DNS & DHCP
Specified in 11 §4.1.

### D8 — Platform health
- CPU (per core, softirq share), memory, disk usage per store (Prometheus/Loki), temperatures.
- conntrack usage, insert failures, early drops; NFQUEUE depth/drops; NFLOG drops.
- Pipeline: Vector buffer usage, events in/out/dropped per stream, Loki ingestion rate/errors,
  scrape health.
- commit-confirm state, last deploy result, current vs previous generation.

## 3. Grafana hardening (also see 08)

- DSH-020 [P0] All human users get the `Viewer` role. The admin account exists only for
  provisioning, its password comes from a secret, and login form access for it MAY be disabled.
- DSH-021 [P0] Disabled: plugin installation (only plugins packaged via Nix), public dashboards,
  external snapshot sharing, anonymous access, gravatar, analytics/reporting/update checks.
- DSH-022 [P0] Explore access for viewers is an explicit option
  (`monitoring.grafana.viewersCanExplore`, default `true`) because log investigation relies on it.

## 4. Alert rules (provisioned)

| Alert | Condition | Severity |
|-------|-----------|----------|
| `CDWExporterDown` | exporter target down 2 m | critical |
| `CDWConntrackNearFull` | entries / max > 85% for 5 m | warning (>95%: critical) |
| `CDWConntrackInsertFailed` | increase > 0 over 5 m | warning |
| `CDWIPSDown` | Suricata not running / no stats 1 m (inspected traffic is being blocked, D-10) | critical |
| `CDWQueueDrops` | NFQUEUE drops > 0.1% of queued | warning |
| `CDWLogPipelineLag` | ingestion lag > 2 m or buffer > 80% | warning |
| `CDWFeedStale` | geo feed > 60 d, signatures > 14 d | warning |
| `CDWConfirmPending` | commit-confirm pending (auto-rollback imminent) | info |
| `CDWRolledBack` | auto-rollback happened | critical |
| `CDWBreakGlassLogin` | admin login via loopback (SEC-010) | warning |
| DNS & DHCP alerts | see 11 §4.2 | — |
| `CDWDenySpike` | denies/s > 5× 1-day baseline | warning |
| `CDWIPSHighSeverity` | any severity-1 alert | warning |

- DSH-030 [P0] Contact points are declared in Nix (email, webhook, Slack/Matrix via webhook);
  secrets via the secrets mechanism (07 §6).
