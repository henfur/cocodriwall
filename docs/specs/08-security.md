# 08 — Security

## 1. Assets
1. Integrity of the enforced policy.
2. Availability of forwarding.
3. Confidentiality of telemetry (IPs, DNS queries, flow metadata = personal data).
4. The management plane (SSH, Grafana, visualizer) and secrets.

## 2. Threat model (abridged)

| Threat | Mitigation |
|--------|------------|
| Attacker on WAN/LAN reaches management services | Services bind only to management-zone addresses (SEC-001) **and** `_mgmt-*` rules restrict `self` access; both, not either. |
| Compromised Grafana account changes policy | No write path exists (NG-1); Grafana is Viewer-only, provisioned read-only. |
| Malicious/compromised config change | Git review, CODEOWNERS, `production` mode clean-tree requirement, signed commits [P1] (`requireSignedRev`). |
| Supply chain (nixpkgs, feeds) | Pinned flake inputs with hashes; `flake.lock` changes reviewed; feed updates as PRs. |
| Log flood / NFLOG DoS | Per-rule log rate limits (DP-070), priority buffering (OBS-040). |
| Malicious traffic exploiting Suricata/parsers | Suricata runs unprivileged with minimal capabilities (CAP_NET_ADMIN only), systemd sandboxing; crashing Suricata blocks inspected traffic rather than bypassing inspection (D-10). |
| Lockout by bad policy | Commit-confirm auto-rollback (07 §3), `_mgmt-*` rules always present. |
| Telemetry interception or injection (remote mode) | Encryption by the infrastructure (WireGuard, Tailscale) or mTLS; Loki/exporter authentication; build warning on unprotected transport (ARCH-012, ARCH-015..017). |
| DNS bypass of FQDN rules or filtering | `dns.enforce` (DP-053, DNS-062). |
| Firewall used as an open resolver / DHCP served to the WAN | No DNS/DHCP listeners on WAN zones (DNS-001, DHCP-003). |
| Client picks a DHCP hostname to gain access | Dynamic names can't be referenced by policy (DHCP-021). |
| DNS rebinding against internal services | Rebinding protection outside local/forward zones (DNS-014). |

## 3. Requirements

- SEC-001 [P0] Prometheus, Loki, Grafana, Vector APIs, exporters bind to loopback or
  management-zone addresses only; the module asserts no listener is bound to `0.0.0.0`/`::`
  except where explicitly configured.
- SEC-002 [P0] nginx terminates TLS for `/grafana/` and `/viz/`. Certificates: declared in Nix
  (from secrets) or ACME (DNS-01) if configured; self-signed generation is a documented fallback.
- SEC-003 [P0] Authentication for both Grafana and the visualizer is OIDC only (D-11):
  `oauth2-proxy` in front of `/grafana/` and `/viz/`, Grafana in auth-proxy mode trusting only
  the loopback proxy; every OIDC user maps to Viewer. Access can be restricted by OIDC group
  claims (`monitoring.oidc.allowedGroups`). No local user accounts exist, and the Grafana login
  form is disabled.
- SEC-004 [P0] SSH: keys only, from management zone only (`_mgmt-ssh`), `PermitRootLogin
  prohibit-password` or disabled; deploy user with restricted sudo for switch/confirm.
- SEC-005 [P0] Every service runs with systemd hardening: `DynamicUser` where possible,
  `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`, `NoNewPrivileges`, minimal
  `CapabilityBoundingSet`, `RestrictAddressFamilies`, `SystemCallFilter=@system-service`.
  A check verifies `systemd-analyze security` exposure ≤ 4.0 for custom services.
- SEC-006 [P0] The visualizer and dashboards expose topology and addressing; they are
  treated as confidential and never served unauthenticated.
- SEC-007 [P0] Kernel hardening sysctls (rp_filter handled by nft fib rule, `accept_redirects=0`,
  `send_redirects=0`, `accept_source_route=0`, `log_martians=1`, `tcp_syncookies=1`).
- SEC-008 [P1] Optional signed-commit enforcement: deploy refuses revisions not signed by keys in
  `operations.trustedSigners`.

## 4. Break-glass access (consequence of D-11)

With OIDC only, an IdP outage, or a branch WAN outage when the IdP is on the internet, locks
everyone out of the dashboards exactly when they are needed most.

- SEC-010 [P0] Break-glass path: the provisioning admin account (DSH-020) is reachable **only**
  on loopback (Grafana listens on `127.0.0.1`; nginx never forwards login-form requests). An
  operator with SSH access via the management zone uses `ssh -L` to log in as admin. Every
  admin login emits a `stream="change"` event and the `CDWBreakGlassLogin` alert.
- SEC-011 [P0] The visualizer is also reachable through the same SSH tunnel on a loopback-only
  nginx vhost without OIDC.
- SEC-012 [P0] The OIDC issuer, client ID and allowed groups are declared in Nix; the client
  secret and cookie secret come from secrets (07 §6). The firewall's own policy MUST allow the
  monitor host to reach the IdP (the analyzer warns if no rule permits `self` → IdP on HTTPS).
