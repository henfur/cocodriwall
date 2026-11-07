# 02 — Policy model (configuration surface)

This is the most important document: it is the product's entire user interface.

## 1. Worked example

```nix
{ ngfw, ... }:
{
  services.ngfw = {
    enable = true;
    siteName = "branch-a";

    zones = {
      wan   = { interfaces = [ "enp1s0" ]; };
      lan   = { interfaces = [ "vlan10" ]; intraZone = "allow"; };
      dmz   = { interfaces = [ "vlan20" ]; };
      guest = { interfaces = [ "vlan30" ]; };
      mgmt  = { interfaces = [ "enp3s0" ]; management = true; };
    };

    objects = {
      hosts.web1      = { addresses = [ "10.20.0.10" "fd00:20::10" ]; };
      networks.users  = { addresses = [ "10.10.0.0/24" "fd00:10::/64" ]; };
      groups.web      = [ "web1" ];
      fqdns.github    = [ "github.com" "githubusercontent.com" ];
      geo.sanctioned  = [ "KP" "IR" ];
    };

    services.custom-api = { tcp = [ 8443 ]; };      # built-ins: ssh, http, https, dns, ntp, ...

    rules = {
      block-sanctioned = {
        priority = 100;
        from = "any"; to = "wan";
        destination = [ "geo:sanctioned" ];
        action = "deny"; log = "deny";
        description = "Compliance: no traffic to sanctioned countries";
      };

      users-web-out = {
        priority = 1000;
        from = "lan"; to = "wan";
        source = [ "users" ];
        services = [ "http" "https" ];
        action = "allow";
        inspect = "ips";
        log = "flow";
      };

      users-no-p2p = {
        priority = 900;
        from = "lan"; to = "wan";
        apps = [ "bittorrent" ];
        action = "deny";
      };

      ci-to-github = {
        priority = 1100;
        from = "dmz"; to = "wan";
        source = [ "web" ];
        destination = [ "fqdn:github" ];
        services = [ "https" "ssh" ];
        action = "allow";
      };

      publish-web = {
        priority = 2000;
        from = "wan"; to = "dmz";
        destination = [ "web1" ];
        services = [ "https" ];
        action = "allow";
        inspect = "ips";
      };
    };

    nat = {
      masquerade.lan-out   = { from = [ "lan" "dmz" "guest" ]; to = "wan"; };
      portForward.web-https = { on = "wan"; port = { tcp = 443; }; to = "web1"; };
    };
  };
}
```

## 2. Zones

| Option | Type | Default | Notes |
|--------|------|---------|-------|
| `zones.<name>.interfaces` | list of str | — | Interface names, VLANs, bridges, WireGuard ifaces, or globs (`wg*`). |
| `zones.<name>.intraZone` | `"allow" \| "deny" \| "rules"` | `"deny"` | Traffic between interfaces of the same zone. `rules` = evaluate rule base. |
| `zones.<name>.management` | bool | `false` | Monitoring/SSH bind here; auto management rules (§8). |
| `zones.<name>.description` | str | `""` | Shown in visualizer. |

- POL-001 [P0] Zone names MUST match `^[a-z][a-z0-9-]{0,31}$`. `any` and `self` are reserved.
- POL-002 [P0] An interface MUST belong to at most one zone. Traffic on interfaces in no zone
  is dropped and counted under reserved rule `_unzoned`.
- POL-003 [P0] `self` represents the firewall itself (nftables `input`/`output`); rules with
  `to = "self"` control access to firewall services.
- POL-004 [P0] At least one zone MUST be `management = true` unless
  `services.ngfw.allowNoManagementZone = true`.

## 3. Address objects

Kinds (each a separate attrset under `objects` so names cannot be ambiguous within a kind):

| Kind | Value | Data-plane realization |
|------|-------|------------------------|
| `hosts` | list of IPv4/IPv6 addresses | anonymous/ named nft set elements |
| `networks` | list of CIDRs | interval set |
| `ranges` | list of `"a.b.c.d-a.b.c.e"` | interval set |
| `groups` | list of object references (any kind, nestable, acyclic) | flattened at IR time |
| `fqdns` | list of domain names; each matches the domain **and all subdomains** (`*.` accepted as alias) | dynamic nft set populated by dnsmasq (03 §7) |
| `geo` | list of ISO-3166 alpha-2 codes, or continent codes `@EU` | interval set from pinned GeoIP DB (03 §8) |

- POL-010 [P0] Object names MUST be globally unique across kinds (so references are unprefixed)
  **or** references use kind prefixes. Proposed: unprefixed for `hosts/networks/ranges/groups`;
  mandatory prefixes `fqdn:` and `geo:` because their semantics differ (dynamic, approximate).
- POL-011 [P0] Inline literals are allowed in rule source/destination: `"10.0.0.0/8"`,
  `"fd00::1"`, `"fqdn:example.com"`, `"geo:DE"`. They appear in the IR as anonymous objects.
- POL-012 [P0] Group cycles MUST fail evaluation with the cycle path in the error.
- POL-013 [P1] Objects MAY declare `zone = "<zone>"`; when set, a rule referencing the object
  with a contradicting `from`/`to` zone is a build error (catches "wrong zone" mistakes).
- POL-014 [P0] Address-family handling: a rule matching only IPv4 objects applies only to IPv4;
  mixing is allowed; `any` means both families.
- POL-015 [P0] In zones that use a delegated IPv6 prefix, IPv6 addresses are written
  prefix-relative (`pd:<zone>::<iid>`, `pd:<zone>`) and resolved at runtime (11 §3.4, DHCP-031).

## 4. Services

```nix
services.<name> = { tcp = [ 443 "8000-8100" ]; udp = [ 443 ]; icmp = [ "echo-request" ]; proto = [ "gre" ]; };
```

- POL-020 [P0] A built-in catalog (`nix/catalogs/services.nix`) MUST ship common services. User
  definitions with the same name override with a warning.
- POL-021 [P0] `services` omitted in a rule ⇒ any protocol/port.

## 5. Applications (App-ID)

Apps are named entries in a catalog (`nix/catalogs/apps.nix`), each mapping to Suricata
detection: an app-layer protocol (`app-layer-protocol:ssh`), and/or TLS SNI / QUIC SNI /
HTTP Host patterns, and/or JA3/JA4 fingerprints.

```nix
apps.zoom = { tlsSni = [ "*.zoom.us" ]; quicSni = [ "*.zoom.us" ]; description = "Zoom"; category = "conferencing"; };
apps.ssh  = { protocol = "ssh"; category = "remote-access"; };
```

- POL-030 [P0] A rule with `apps` set MUST have `inspect` implicitly forced to `ips` (apps can
  only be enforced inline). Setting `inspect = "none"` with `apps` is a build error.
- POL-031 [P0] App matching is **eventual**: the first packets of a flow are allowed while
  detection runs; enforcement drops the flow once identified. This MUST be documented in the
  visualizer for every app rule ("enforced after detection").
- POL-032 [P0] `allow` rules with `apps` mean: "flows matching the L3/L4 part are inspected;
  flows whose detected app is **not** in the list are dropped" (app allow-listing). The flow
  gets `app-unknown` handling configurable per rule: `onUnknownApp = "allow" | "deny"`
  (default `deny`) after `detectionTimeout` packets/bytes.
- POL-033 [P1] App categories (`apps = [ "category:p2p" ]`) MAY be referenced.

> OPEN-2: Is the Suricata app-layer + SNI catalog sufficient, or must v1 include nDPI-based
> detection (Suricata 8 nDPI plugin) for a broader catalog? Recommendation: ship v1 with
> Suricata-native + SNI catalog (~50 apps), make nDPI a P1 behind an option.

## 6. Rules

| Option | Type | Default | Notes |
|--------|------|---------|-------|
| `rules.<id>` | submodule | — | Attribute name = rule ID, stable forever. |
| `priority` | int 1–65000 | — (required) | Lower = evaluated first. Ties broken by ID (lexicographic) **with a warning**. |
| `from`, `to` | zone name, list of zones, or `"any"` | — (required) | |
| `source`, `destination` | list of object refs / literals | `[ "any" ]` | |
| `services` | list of service refs or inline `{ tcp = [..]; }` | any | |
| `apps` | list of app refs | `[]` | §5 |
| `action` | `"allow" \| "deny" \| "reject"` | — (required) | `reject` sends TCP RST / ICMP unreachable. |
| `inspect` | `"none" \| "ips"` (`"ids"` in P1) | `"none"` | `ips` = inline through Suricata (03 §5). Per-rule alert-only `ids` is P1 (DP-036). |
| `log` | `"none" \| "deny" \| "flow" \| "sampled"` | `deny` rules: `"deny"`; `allow`: `"flow"` | 04 §3 |
| `enabled` | bool | `true` | Disabled rules stay in IR (shown greyed in visualizer). |
| `description` | str | `""` | |
| `owner`, `ticket`, `tags` | str / str / list | — | Free metadata, shown in visualizer and logs. |
| `expires` | ISO date | `null` | Build **fails** after this date unless `enabled = false` (forces cleanup of temporary rules). |
| `schedule` | `{ days; from; to; tz }` | `null` | [P2] time-based rules via nft `meta hour/day`. |

- POL-040 [P0] Evaluation is **first match by `(priority, id)`** within the `(from, to)` zone
  pair; rules with `from/to = any` participate in every pair at their priority.
- POL-041 [P0] Rule IDs MUST match `^[a-z0-9][a-z0-9-]{0,62}$`. IDs starting with `_` are reserved
  for system rules (`_default-deny`, `_unzoned`, `_invalid-state`, `_mgmt-*`, `_established`).
- POL-042 [P0] Default action after the last rule is deny with ID `_default-deny`, logged with
  `log = "deny"` (rate-limited). Per zone pair overrides are not allowed in v1 (use an explicit
  final rule instead).
- POL-043 [P0] Rules MAY be declared in any number of NixOS modules; attrset merging makes
  duplicate IDs a type error (desired).
- POL-044 [P1] `services.ngfw.ruleDefaults` MAY set defaults for `log`, `inspect`, `owner`.

Why an attrset and not a list (D-5): NixOS merges lists from multiple modules in module-import
order, which is invisible in review and makes "insert a rule between two others" fragile.
Explicit priorities make ordering explicit in the diff.

## 7. NAT

| Option | Notes |
|--------|-------|
| `nat.masquerade.<id> = { from; to; source?; }` | SNAT to egress interface address. |
| `nat.snat.<id> = { from; to; source?; translateTo; }` | Static SNAT to address/pool. |
| `nat.portForward.<id> = { on; port; to; toPort?; source?; }` | DNAT. **Does not** imply allow. |
| `nat.oneToOne.<id>` | [P1] Bidirectional static NAT. |
| `nat.nptv6.<id>` | [P2] IPv6 prefix translation. |

- POL-050 [P0] Filter rules match **post-DNAT** (real) destination addresses, i.e. a port
  forward to `web1` requires an allow rule with `destination = [ "web1" ]`. The analyzer MUST
  warn on any port forward with no allow rule that permits it.
- POL-051 [P0] NAT entries have IDs and appear in the visualizer and in flow logs
  (`nat_rule` field).

## 8. System and management rules

- POL-060 [P0] The module MUST generate, in reserved priority band 1–99:
  - `_established`: allow `ct state established,related` (before all user rules).
  - `_invalid-state`: drop `ct state invalid` (logged, rate-limited).
  - `_mgmt-ssh`, `_mgmt-https`: allow management zone → `self` on SSH and HTTPS (Grafana/visualizer).
  - `_fw-dns`: allow zones with `dns.serve` → `self` on DNS (11).
  - `_dhcp4`, `_dhcp6`: allow DHCP to `self` from zones with DHCP enabled (DHCP-004).
  - `_icmpv6-essential`: allow ICMPv6 ND/RA/PMTU types required by RFC 4890.
- POL-061 [P0] System rules are visible in the IR and visualizer, tagged `system = true`.
- POL-062 [P0] `_mgmt-*` rules MAY be restricted by `services.ngfw.management.allowedSources`
  but MUST NOT be disabled while a commit-confirm is pending (07 §3).

## 9. Validation (build-time)

| ID | Check | Severity |
|----|-------|----------|
| VAL-01 | Unknown zone / object / service / app reference | error |
| VAL-02 | Group cycle | error |
| VAL-03 | Interface in multiple zones | error |
| VAL-04 | Invalid address / CIDR / port / country code | error |
| VAL-05 | `apps` with `inspect = "none"` | error |
| VAL-06 | `expires` in the past and rule enabled | error |
| VAL-07 | Numeric rule tag collision (03 §3) | error (with hint to set `tag`) |
| VAL-08 | `nft -c` rejects ruleset | error |
| VAL-09 | Rule fully shadowed by an earlier rule | warning; error if `strict = true` |
| VAL-10 | Rule redundant (removing it does not change any verdict) | warning |
| VAL-11 | Overly broad allow (`any` → `any`, any service) from a non-management zone | error unless `acknowledgeBroad = "reason"` |
| VAL-12 | Port forward without matching allow rule | warning |
| VAL-13 | Equal priority between rules that overlap | warning |
| VAL-14 | FQDN object used in a rule whose source zone has no `dns.serve` | error |
| VAL-15 | Object `zone` contradicts rule zones (POL-013) | error |
| VAL-16 | DNS & DHCP checks: DNS-013, DNS-031, DNS-033, DHCP-003, DHCP-010, DHCP-021 (11) | error |

- POL-070 [P0] Evaluation-time checks (VAL-01..06, 14, 15) are performed in Nix with errors that
  name the rule ID and option path. Analysis checks (VAL-07..13) run in `ngfw-compile` and fail
  the derivation with a human-readable report.
- POL-071 [P0] `services.ngfw.strict` (default `false`, recommended `true` in production)
  promotes all warnings to errors.

## 10. IR (`policy.json`)

- POL-080 [P0] The IR schema is defined as Rust types in `crates/ngfw-ir`, from which a JSON
  Schema is generated and committed; the Nix module output is validated against it in `checks`.
- POL-081 [P0] IR contents: `schema_version`, `site`, `policy_hash`, `generated_from` (git rev
  if available, else `dirty`), zones (with interfaces), fully flattened objects (with
  provenance: which group/literal), services, apps, rules sorted in evaluation order (with
  numeric `tag`, `sid_range`, resolved fields, original refs for display), NAT, system rules,
  and the source location (`file:line`) of each rule when Nix can provide it
  (`builtins.unsafeGetAttrPos`).
- POL-082 [P0] IR versioning: `schema_version` is semver; the visualizer and exporter MUST refuse
  a major version they do not support with a clear message.
- POL-083 [P0] The IR includes a routing snapshot (connected networks and static routes per
  zone, derived from the NixOS networking config) used by the visualizer's path tracer
  (06 §4.3) and by the analyzer to map objects to zones.
