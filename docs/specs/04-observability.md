# 04 — Observability

## 1. Signals

| Signal | Producer | Transport | Store | Purpose |
|--------|----------|-----------|-------|---------|
| Host & interface metrics | node_exporter | scrape | Prometheus | Throughput, pps, errors, CPU, memory, disk |
| Firewall metrics | `cdw-exporter` | scrape | Prometheus | Per-rule hits, conntrack, sets, queues, policy info, feed age |
| Suricata stats | Suricata eve `stats` | Vector → `prometheus_exporter` sink | Prometheus | Capture/decoder/flow/app-layer counters, kernel drops |
| Decision logs | nft `log group` → ulogd2 (NFLOG) | Vector | Loki | Every deny/reject (rate-limited) |
| Flow logs | conntrack events → ulogd2 (NFCT) | Vector | Loki | Allowed flows (start/end, bytes, duration) |
| IPS events | Suricata eve `alert`, `drop`, `anomaly` | Vector | Loki | Threat detection |
| App events | Suricata eve `flow`, `tls`, `quic` | Vector | Loki | Detected app / SNI per flow |
| DNS logs | dnsmasq query log | Vector | Loki | Queries, blocks, FQDN-rule troubleshooting (11 §4) |
| DHCP logs | dnsmasq DHCP log | Vector | Loki | Lease events (11 §4) |
| DNS/DHCP metrics | dnsmasq + Unbound exporters, `cdw-exporter` | scrape | Prometheus | Cache, DNSSEC, upstream, pool usage (11 §4) |
| Change events | `cdw-activate` hook | Vector | Loki | Policy applied / rolled back → Grafana annotations |
| System journal | journald | Vector | Loki | Service failures |

- OBS-001 [P0] All timestamps UTC, RFC 3339 with milliseconds. chrony MUST be enabled.
- OBS-002 [P0] Every log record and every `cdw_*` metric carries `firewall` (= `siteName`, or
  hostname if unset).

## 2. `cdw-exporter` metrics

| Metric | Type | Labels | Source |
|--------|------|--------|--------|
| `cdw_rule_hits_total` | counter | `rule, action, from_zone, to_zone` | nft named counters (packets = new flows, DP-022) |
| `cdw_rule_last_hit_timestamp_seconds` | gauge | `rule` | exporter-tracked delta |
| `cdw_rule_info` | gauge=1 | `rule, priority, action, inspect, owner, system, enabled, expires` | IR |
| `cdw_policy_info` | gauge=1 | `policy_hash, generation, git_rev, schema_version` | IR + system profile |
| `cdw_set_elements` | gauge | `set, kind (object/fqdn/geo)` | `nft -j list sets` |
| `cdw_conntrack_entries`, `cdw_conntrack_max` | gauge | — | `/proc/sys/net/netfilter` |
| `cdw_conntrack_events_total` | counter | `type (insert_failed, drop, early_drop, …)` | conntrack stats (netlink) |
| `cdw_nfqueue_packets_total`, `cdw_nfqueue_dropped_total` | counter | `queue, reason (kernel, user)` | `/proc/net/netfilter/nfnetlink_queue` |
| `cdw_log_dropped_total` | counter | `source (nflog, nfct)` | ulogd2 stats |
| `cdw_feed_age_seconds`, `cdw_feed_info` | gauge | `feed, version` | IR |
| `cdw_confirm_pending` | gauge | — | commit-confirm state (07 §3) |
| `cdw_offloaded_flows` | gauge | — | [P1] sampled conntrack `OFFLOAD` count |

- OBS-010 [P0] Scrape cost: the exporter MUST answer in < 500 ms with 5 000 rules and MUST NOT
  dump the conntrack table on scrape.
- OBS-011 [P0] Cardinality budget per firewall: ≤ 50 000 active series total. Rule metrics
  scale with rule count (~4 series/rule); address-level labels (IPs, ports, FQDNs) are
  **forbidden** in Prometheus — they live in Loki.

## 3. Log schema

All log streams are normalized by Vector to a common JSON schema (ECS-inspired, flattened):

| Field | Type | Present in | Notes |
|-------|------|------------|-------|
| `ts` | time | all | |
| `firewall` | str | all | |
| `stream` | enum | all | `decision`, `flow`, `ips`, `app`, `dns`, `dhcp`, `change`, `system` |
| `policy_hash` | str | decision, flow, ips | Generation active at event time |
| `rule_id` | str | decision, flow, ips | Resolved from tag/SID via `rule-map.json` |
| `rule_tag` | hex | decision, flow | Raw, for audit |
| `action` | enum | decision, flow, ips | `allow`, `deny`, `reject`, `alert`, `drop` |
| `from_zone`, `to_zone` | str | decision, flow, ips | From interface→zone map in IR |
| `in_if`, `out_if` | str | decision, flow | |
| `proto` | str | decision, flow, ips | |
| `src_ip`, `src_port`, `dst_ip`, `dst_port` | str/int | decision, flow, ips | Original (pre-NAT) |
| `nat_src_ip`, `nat_src_port`, `nat_dst_ip`, `nat_dst_port`, `nat_rule` | | flow | Post-NAT, when NAT applied |
| `src_geo`, `dst_geo` | str (CC) | decision, flow, ips | Vector enrichment from the same pinned DB |
| `app` | str | flow, app, ips | From Suricata; joined to flow by `community_id` |
| `sni`, `fqdn` | str | flow, app, dns | |
| `bytes_out`, `bytes_in`, `pkts_out`, `pkts_in`, `duration_ms` | int | flow (end) | From conntrack accounting |
| `flow_event` | enum | flow | `start`, `end` |
| `sample_rate` | int | decision, flow | `N` when the record is 1 of N (POL-045, `log = "sampled"`); absent when unsampled. Dashboards multiply counts by it. |
| `community_id` | str | flow, ips, app | Community ID v1 for cross-stream joins |
| `sig_id`, `sig_rev`, `sig_msg`, `sig_class`, `severity` | | ips | |
| `generation`, `actor`, `result` | | change | |

- OBS-020 [P0] The schema is versioned (`schema = "cdw.log/1"`) and documented as JSON Schema in
  `crates/cdw-ir`; Vector transforms are unit-tested against fixtures (Vector `tests` blocks).
- OBS-021 [P0] `rule_id` resolution uses the `rule-map.json` of the **generation recorded in the
  ct mark's tag**; since tags are ID-hashed (DP-010), flows outliving a policy change still
  resolve correctly unless the rule was deleted, in which case `rule_id = "<deleted:tag>"`.
  Vector keeps the last N (default 20) rule maps.
- OBS-022 [P0] Flow-end records for flows lasting longer than 1 h are known to attribute all
  bytes at end time. [P1] The exporter emits interim `flow_event = "update"` records for
  long-lived flows by sampling conntrack filtered by `LOG_FLOW` mark every 5 min.
- OBS-023 [P0] Loki labels are restricted to: `firewall, stream, action, from_zone, to_zone`.
  Everything else is structured metadata or line content. (≤ ~1 000 streams per firewall.)

### 3.4 Logging levels per rule (from 02 §6)

| `log` | Decision log | Flow start | Flow end |
|-------|--------------|------------|----------|
| `none` | — | — | — |
| `deny` | yes (deny/reject rules) | — | — |
| `flow` | n/a | yes | yes |
| `sampled` | n/a | 1/N | 1/N |

## 4. Derived metrics

- OBS-030 [P0] Loki ruler recording rules (remote-written to Prometheus) produce low-cardinality
  aggregates from logs: `cdw:zone_pair_bytes:rate5m{from_zone,to_zone}`,
  `cdw:app_bytes:rate5m{app}` (top 50 apps only, rest `other`),
  `cdw:denies:rate5m{rule}`, `cdw:ips_alerts:rate5m{severity}`.
- OBS-031 [P0] Top-talker / top-destination / top-country / top-FQDN views are LogQL `topk`
  queries over Loki at dashboard time, never Prometheus series.

## 5. Pipeline reliability

- OBS-040 [P0] Vector uses disk buffers per sink; on overflow it drops by priority:
  `flow`/`app` first, then `dns`/`dhcp`, never `decision`/`ips`/`change` until the hard cap.
  Drops are exported as metrics.
- OBS-041 [P0] Alerts (05 §4) fire on: pipeline lag > 2 min, buffer > 80%, exporter down,
  Loki ingestion errors.
- OBS-042 [P0] Telemetry failure MUST NOT affect forwarding (ulogd2/Vector/Loki down ⇒ NFLOG
  drops are counted, nothing blocks).

## 6. Retention and sizing

| Data | `local` default | `remote` default |
|------|-----------------|------------------|
| Prometheus | 30 d | 395 d |
| Loki `decision`, `ips`, `change` | 14 d | 180 d |
| Loki `flow`, `app` | 3 d | 30 d |
| Loki `dns`, `dhcp`, `system` | 3 d | 30 d |

(`local` defaults are sized for the 8 GB reference with a 100 GB disk, D-9.)

- OBS-050 [P0] Per-stream retention is configurable; the module computes and documents an
  estimated disk requirement at build time (`build.sizingReport`) from configured retention and
  a user-provided `monitoring.expectedFlowsPerSecond` (rule of thumb: ~40 bytes/flow-record
  after Loki compression ⇒ 1 000 flows/s with `log = "flow"` ≈ 7 GB/day).
- OBS-051 [P0] Logs contain personal data (IPs, DNS names). Retention defaults MUST be
  documented as a privacy decision, and `monitoring.privacy.anonymizeSourceIps` [P1] can hash
  internal source IPs in `flow`/`dns` streams.
