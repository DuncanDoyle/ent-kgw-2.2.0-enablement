# Web Application Firewall (WAF)

This use-case demonstrates the **Coraza/OWASP CRS WAF** capability of **Solo Enterprise for kgateway 2.2.x**. The WAF runs as an Envoy ExtProc (external processor) sidecar that inspects HTTP requests before they reach the backend.

Three complementary demos are included, each on its own hostname:

| Hostname | Demo |
|---|---|
| `waf.example.com` | OWASP CRS (XSS, SQLi, LFI) + custom Coraza rules |
| `ip-filter.example.com` | IP blocklist using `REMOTE_ADDR @ipMatch` |
| `custom-rules.example.com` | JSON body inspection + ConfigMap-based rule hot-reload |

## Architecture

```
                    ┌──────────────────────────────────────────────┐
                    │  Gateway gw (waf, port 8080)                 │
                    │  GatewayClass: enterprise-kgateway-waf       │
                    │                                               │
                    │  EnterpriseKgatewayParameters:               │
                    │    waf.enabled: true                         │
                    │                                               │
                    │  ┌────────────────────────────────────────┐  │
                    │  │ ListenerPolicy xff-trust                │  │
                    │  │ useRemoteAddress: true                  │  │
                    │  │ xffNumTrustedHops: 1                    │  │
                    │  └────────────────────────────────────────┘  │
                    └──────────────────────────────────────────────┘
                         │               │                │
                  HTTPRoute        HTTPRoute         HTTPRoute
                waf.example.com  ip-filter.example.com  custom-rules.example.com
                         │               │                │
                         ▼               ▼                ▼
                        WAFPolicy     WAFPolicy        WAFPolicy
                      (CRS + custom)  (IP blocklist)  (body inspect, hot-reload)
                         │               │                │
                         └───────────────┴────────────────┘
                                         │
                                  httpbin (waf-httpbin)
```

The WAF ExtProc server (`waf-server`) runs as a separate Deployment in `kgateway-system`. It is instantiated per GatewayClass — creating the `enterprise-kgateway-waf` GatewayClass starts a dedicated WAF server, leaving gateways on the default class unaffected.

## Resources

| Resource | Kind | Namespace | Purpose |
|---|---|---|---|
| `ent-kgateway-waf-params` | EnterpriseKgatewayParameters | `kgateway-system` | Enables WAF ExtProc server |
| `enterprise-kgateway-waf` | GatewayClass | cluster-scoped | Points at `ent-kgateway-waf-params` |
| `gw` | Gateway | `waf` | Listens on port 8080 |
| `xff-trust` | ListenerPolicy | `waf` | Sets XFF trust so REMOTE_ADDR reflects real client IP |
| `httpbin` | HTTPRoute | `waf` | Routes `waf.example.com` to httpbin |
| `ip-filter` | HTTPRoute | `waf` | Routes `ip-filter.example.com` to httpbin |
| `custom-rules` | HTTPRoute | `waf` | Routes `custom-rules.example.com` to httpbin |
| `httpbin-waf` | WAFPolicy | `waf` | OWASP CRS 4.21.0 + custom User-Agent rule |
| `ip-filter-waf` | WAFPolicy | `waf` | IP blocklist: blocks `1.2.3.4` |
| `custom-rules-waf` | WAFPolicy | `waf` | Body inspection (HeadersAndBody), ConfigMap-backed rules |
| `httpbin-waf` | EnterpriseKgatewayTrafficPolicy | `waf` | Attaches `httpbin-waf` WAFPolicy to the httpbin HTTPRoute |
| `ip-filter-waf` | EnterpriseKgatewayTrafficPolicy | `waf` | Attaches `ip-filter-waf` to the ip-filter HTTPRoute |
| `custom-rules-waf` | EnterpriseKgatewayTrafficPolicy | `waf` | Attaches `custom-rules-waf` to the custom-rules HTTPRoute |
| `custom-waf-rules` | ConfigMap | `waf` | Hot-reloadable rule engine config + custom Coraza rules |
| `httpbin` | Deployment/Service | `waf-httpbin` | Backend API |

## WAFPolicy Design

### Demo 1 — OWASP CRS + Custom Rules (`waf.example.com`)

Runs the full OWASP CRS 4.21.0 in blocking mode (`SecRuleEngine On`). Two CRS rules are removed to avoid false positives in this environment:

- **913100** (Scanner detection) — flags `curl` User-Agent; removed to avoid false positives during demos
- **920430** (HTTP protocol version validation) — removed because the ExtProc does not forward the original protocol version string

A custom Coraza rule (`id:5001`) is layered on top of CRS to block requests with `User-Agent: bad-bot`, demonstrating that custom rules and the CRS can coexist in the same WAFPolicy.

### Demo 2 — IP Filtering (`ip-filter.example.com`)

Blocks requests from IP address `1.2.3.4` using `REMOTE_ADDR @ipMatch`. For this to work correctly, the `ListenerPolicy` sets `useRemoteAddress: true` and `xffNumTrustedHops: 1`, which tells Envoy to strip its own IP from the `X-Forwarded-For` chain before forwarding the request to the WAF server. Without this, `REMOTE_ADDR` in Coraza would always be Envoy's own hop IP.

### Demo 3 — Body Inspection + Hot-Reload (`custom-rules.example.com`)

Demonstrates two advanced features:

**Body inspection:** The WAFPolicy sets `processingConfig.request.mode: HeadersAndBody`, which buffers the full request body so phase:2 rules can inspect it. A rule inspects `ARGS:json.secret` in JSON POST bodies and blocks requests containing `leaked-secret`.

**Hot-reload:** Rules are stored in a ConfigMap (`custom-waf-rules`) rather than inline in the WAFPolicy. The WAF server picks up ConfigMap changes without requiring a WAFPolicy redeployment. The demo script updates the ConfigMap's blocked pattern and shows the rule change taking effect within a few seconds.

## Setup

**Prerequisites:** Solo Enterprise for kgateway 2.2.x installed. No other use-case setup required — this demo creates its own GatewayClass.

```sh
cd use-cases/waf
sh install/setup.sh
```

The setup script:
1. Deploys `EnterpriseKgatewayParameters` with `waf.enabled: true` and the `enterprise-kgateway-waf` GatewayClass
2. Waits for the WAF server Deployment to become ready
3. Creates namespaces `waf` and `waf-httpbin`
4. Deploys the Gateway, ListenerPolicy, httpbin backend, and ReferenceGrant
5. Deploys all three HTTPRoutes, WAFPolicies, and TrafficPolicies
6. Deploys the custom rules ConfigMap

To tear down:

```sh
sh install/teardown.sh
```

## Running the Demo

### Get the Gateway IP

```sh
export GW_IP=$(kubectl get gateway gw -n waf -o jsonpath='{.status.addresses[0].value}')
echo $GW_IP
```

### Demo 1 — OWASP CRS (`waf.example.com`)

```sh
sh curl-requests.sh
```

The script demonstrates five scenarios:

**Normal request** — no attack patterns. Expected: `200 OK`.
```sh
curl -si "http://${GW_IP}:8080/get" -H "host: waf.example.com"
```

**Local File Inclusion (LFI)** — path matches CRS rule 930130. Expected: `403 Forbidden`.
```sh
curl -si "http://${GW_IP}:8080/.htaccess" -H "host: waf.example.com"
```

**SQL injection in query string** — CRS 942xxx rules. Expected: `403 Forbidden`.
```sh
curl -si "http://${GW_IP}:8080/get?id=1' OR '1'='1" -H "host: waf.example.com"
```

**XSS in query string** — CRS 941xxx rules. Expected: `403 Forbidden`.
```sh
curl -si "http://${GW_IP}:8080/get?q=<script>alert(1)</script>" -H "host: waf.example.com"
```

**Custom User-Agent block** — blocked by the custom `id:5001` rule, not CRS. Expected: `403 Forbidden`.
```sh
curl -si "http://${GW_IP}:8080/get" -H "host: waf.example.com" -H "User-Agent: bad-bot"
```

After running, check the WAF server logs to see the blocked request details:
```sh
kubectl logs -n kgateway-system deploy/waf-server-enterprise-kgateway-waf --tail=20
```

### Demo 2 — IP Filtering (`ip-filter.example.com`)

```sh
sh curl-ip-filter-demo.sh
```

**Normal request** — no blocked IP. Expected: `200 OK`.
```sh
curl -si "http://${GW_IP}:8080/get" -H "host: ip-filter.example.com"
```

**Request from blocked IP** — `X-Forwarded-For: 1.2.3.4`. Expected: `403 Forbidden`.
```sh
curl -si "http://${GW_IP}:8080/get" \
  -H "host: ip-filter.example.com" \
  -H "X-Forwarded-For: 1.2.3.4"
```

**Request from non-blocked IP** — `X-Forwarded-For: 5.6.7.8`. Expected: `200 OK`.
```sh
curl -si "http://${GW_IP}:8080/get" \
  -H "host: ip-filter.example.com" \
  -H "X-Forwarded-For: 5.6.7.8"
```

> **How it works:** The `ListenerPolicy` with `useRemoteAddress: true` and `xffNumTrustedHops: 1` tells Envoy to strip its own appended IP from the XFF chain, leaving the client-supplied IP as `REMOTE_ADDR` for Coraza to evaluate.

### Demo 3 — Body Inspection + Hot-Reload (`custom-rules.example.com`)

```sh
sh curl-custom-rules-demo.sh
```

**POST with clean body** — `secret` field does not match the blocked pattern. Expected: `200 OK`.
```sh
curl -si "http://${GW_IP}:8080/post" \
  -H "host: custom-rules.example.com" \
  -H "Content-Type: application/json" \
  -d '{"secret": "my-safe-value"}'
```

**POST with blocked pattern** — `secret` contains `leaked-secret`. Expected: `403 Forbidden`.
```sh
curl -si "http://${GW_IP}:8080/post" \
  -H "host: custom-rules.example.com" \
  -H "Content-Type: application/json" \
  -d '{"secret": "leaked-secret"}'
```

**Hot-reload** — the script patches the ConfigMap to block a different pattern, waits 5 seconds for the WAF server to pick up the change, then shows that the previously blocked payload now passes and a new one is blocked — without redeploying anything.

## Utility Scripts

**`get-crs-version.sh`** — extracts the embedded OWASP CRS version from the WAF server image. The container is distroless (no shell), so the script uses `docker create` + `docker cp` + `strings` to inspect the binary.

```sh
sh get-crs-version.sh
```

Expected output includes `OWASP_CRS/4.21.0`.

## Key Learning Points

- The WAF is enabled per-GatewayClass via `EnterpriseKgatewayParameters` — creating a dedicated class gives WAF to some gateways without affecting others.
- WAFPolicy is attached to routes via `EnterpriseKgatewayTrafficPolicy`, keeping WAF configuration separate from routing configuration.
- `REMOTE_ADDR` in Coraza reflects the Envoy-appended IP, not the real client IP, unless a `ListenerPolicy` with `useRemoteAddress: true` and `xffNumTrustedHops: 1` is applied.
- Body inspection (phase:2 rules against `ARGS:json.*`) requires `processingConfig.request.mode: HeadersAndBody` — it is off by default to avoid latency overhead.
- ConfigMap-backed rules reload without a WAFPolicy redeploy, enabling rule updates with zero downtime and no Kubernetes reconciliation cycle.
