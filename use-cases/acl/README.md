# IP-Based Access Control (ACL)

This use-case demonstrates IP-based access control in **Solo Enterprise for kgateway 2.2.x**. ACL policies are attached to HTTPRoutes via `EnterpriseKgatewayTrafficPolicy` and evaluated inline by the Envoy proxy — no external server is required.

## How It Works

ACL evaluation happens at Layer 7, after the Gateway routes the request but before it reaches the backend. The policy inspects the client IP (derived from the peer address or, when configured, from `X-Forwarded-For`) and takes a per-request allow/deny decision.

**Longest-prefix matching determines the outcome.** When a client IP matches multiple CIDR rules, the most specific prefix wins — a `/32` rule takes precedence over a `/16` rule regardless of the order rules are written in the policy.

```
Client request
      │
      ▼
 Gateway listener (XFF trust via ListenerPolicy)
      │
      ▼
 Route match (HTTPRoute)
      │
      ▼
 ACL filter evaluates client IP
      ├── match found → apply rule action (allow / deny)
      └── no match → apply defaultAction
            ├── allow → forward to backend
            └── deny → 403 response (+ optional X-Blocked-By header)
```

## What This Demo Shows

Three ACL patterns are demonstrated, each on a separate HTTPRoute:

| Path | Pattern | defaultAction | Rule |
|---|---|---|---|
| `/get` | No ACL | — | Baseline — any IP allowed |
| `/headers` | Allowlist | `deny` | Allow `10.10.0.0/16`, deny everything else |
| `/anything` | Denylist | `allow` | Deny `10.10.0.0/16`, allow everything else |
| `/uuid` | Hole-punching | `allow` | Deny `10.10.0.0/16`, but allow `10.10.5.100/32` specifically |

### XFF-based IP simulation

On Minikube all traffic originates from within the cluster. A `ListenerPolicy` configures Envoy to treat the `X-Forwarded-For` header as the client IP (`useRemoteAddress: true`, `xffNumTrustedHops: 1`). This lets the demo script send `-H "X-Forwarded-For: <ip>"` to simulate requests from any address without needing actual clients at those IPs.

In production behind a trusted load balancer, the same `ListenerPolicy` setting causes ACL to evaluate the real client IP carried in XFF by the LB.

## ACL Policy Fields

| Field | Purpose |
|---|---|
| `acl.defaultAction` | Fallback when no rule matches: `allow` or `deny` |
| `acl.rules[].name` | Optional rule identifier — appears in `X-Blocked-By` response header and Envoy access logs |
| `acl.rules[].cidrs` | CIDR blocks or bare IPs (treated as `/32` / `/128`) |
| `acl.rules[].action` | Per-rule decision: `allow` or `deny` |
| `acl.denyResponse.statusCode` | HTTP status on denial (default `403`) |
| `acl.denyResponse.blockedByHeaderName` | Response header that carries the matched rule name on denial |

### Deny response header

When `blockedByHeaderName` is set, a denied response includes that header with the value:
- the matched rule's `name` field (e.g., `block-internal`)
- `"rule"` for unnamed rules
- `"default"` when the default action is applied

This is useful for debugging which rule triggered and for structured access log queries.

### Metrics and access logs

Denied requests increment the Envoy counter `dev.kgateway.http.acl.blocked`, readable from the Envoy admin interface at `http://localhost:19000/stats` (accessible from inside the pod or via the debug sidecar pattern shown in the overlays use-case).

Denial events also write the matched rule name to Envoy dynamic metadata under `dev.kgateway.http.acl:blocked-by`, which can be referenced in access log format strings with `%DYNAMIC_METADATA(dev.kgateway.http.acl:blocked-by)%`.

## Resources

| Resource | Kind | Namespace | Purpose |
|---|---|---|---|
| `ent-kgateway-acl-params` | EnterpriseKgatewayParameters | `kgateway-system` | No shared extensions needed for ACL |
| `enterprise-kgateway-acl` | GatewayClass | cluster-scoped | Points at `ent-kgateway-acl-params` |
| `gw` | Gateway | `acl` | Listens on port 80 |
| `xff-trust` | ListenerPolicy | `acl` | Configures XFF trust for accurate client IP evaluation |
| `httpbin-default` | HTTPRoute | `acl` | `/get` — no ACL (baseline) |
| `httpbin-allowlist` | HTTPRoute | `acl` | `/headers` — allowlist policy attached |
| `httpbin-denylist` | HTTPRoute | `acl` | `/anything` — denylist policy attached |
| `httpbin-holepunch` | HTTPRoute | `acl` | `/uuid` — hole-punch policy attached |
| `httpbin-allowlist` | EnterpriseKgatewayTrafficPolicy | `acl` | Allowlist: allow `10.10.0.0/16`, deny rest |
| `httpbin-denylist` | EnterpriseKgatewayTrafficPolicy | `acl` | Denylist: deny `10.10.0.0/16`, allow rest |
| `httpbin-holepunch` | EnterpriseKgatewayTrafficPolicy | `acl` | Hole-punch: deny `/16`, allow `10.10.5.100/32` |
| `httproute-acl-service` | ReferenceGrant | `acl-httpbin` | Allows HTTPRoutes in `acl` to reference the httpbin Service |
| `httpbin` | Deployment/Service | `acl-httpbin` | Backend API |

## Configuration

### Allowlist

```yaml
spec:
  acl:
    defaultAction: deny              # deny everything by default
    rules:
    - name: allow-internal
      cidrs:
      - "10.10.0.0/16"
      action: allow                  # only this range gets through
    denyResponse:
      statusCode: 403
      blockedByHeaderName: X-Blocked-By
```

### Denylist

```yaml
spec:
  acl:
    defaultAction: allow             # allow everything by default
    rules:
    - name: block-internal
      cidrs:
      - "10.10.0.0/16"
      action: deny                   # this range is blocked
    denyResponse:
      statusCode: 403
      blockedByHeaderName: X-Blocked-By
```

### Hole-punching

```yaml
spec:
  acl:
    defaultAction: allow
    rules:
    - name: block-subnet
      cidrs:
      - "10.10.0.0/16"
      action: deny
    - name: allow-exception
      cidrs:
      - "10.10.5.100/32"            # /32 beats /16 — longest prefix wins
      action: allow
    denyResponse:
      statusCode: 403
      blockedByHeaderName: X-Blocked-By
```

> **Rule order does not matter for overlapping CIDRs.** The most specific prefix always wins. A `/32` allow exception overrides a `/16` deny block regardless of which rule appears first in the list.

## Setup

**Prerequisites:** Solo Enterprise for kgateway 2.2.x installed.

```sh
cd use-cases/acl
sh install/setup.sh
```

To tear down:

```sh
sh install/teardown.sh
```

## Running the Demo

### 1. Run the demo script

```sh
sh curl-acl-demo.sh
```

Expected output (trimmed):

```
================================================================
 Baseline — no ACL policy (/get)
================================================================

--- Any IP, expect 200 ---
HTTP/1.1 200 OK

--- Any IP, expect 200 ---
HTTP/1.1 200 OK

================================================================
 Allowlist — allow 10.10.0.0/16, deny everything else (/headers)
================================================================

--- 10.10.0.1 (in allowed /16), expect 200 ---
HTTP/1.1 200 OK

--- 192.168.1.1 (not in allowed /16), expect 403 + X-Blocked-By: default ---
HTTP/1.1 403 Forbidden
X-Blocked-By: default

================================================================
 Denylist — deny 10.10.0.0/16, allow everything else (/anything)
================================================================

--- 10.10.0.1 (in blocked /16), expect 403 + X-Blocked-By: block-internal ---
HTTP/1.1 403 Forbidden
X-Blocked-By: block-internal

--- 192.168.1.1 (not in blocked /16), expect 200 ---
HTTP/1.1 200 OK

================================================================
 Hole-punching — /32 exception inside a blocked /16 (/uuid)
================================================================

--- 10.10.1.1 (in blocked /16, no exception), expect 403 ---
HTTP/1.1 403 Forbidden
X-Blocked-By: block-subnet

--- 10.10.5.100 (/32 exception overrides /16 block), expect 200 ---
HTTP/1.1 200 OK
```

### 3. Inspect ACL counters in Envoy admin

```sh
POD=$(kubectl get pods -n acl -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n acl "$POD" -- wget -qO- http://localhost:19000/stats \
  | grep acl
```

The `dev.kgateway.http.acl.blocked` counter increments for each denied request.

## Key Learning Points

- ACL is enforced **inline in Envoy** — no external sidecar, no WAF server, no round-trip. Evaluation cost is negligible.
- **defaultAction** is the most important field: allowlist patterns use `deny`, denylist patterns use `allow`.
- **Longest-prefix matching** means rule order is irrelevant for overlapping CIDRs. Write the most specific rule at any position and it will take precedence.
- The `blockedByHeaderName` field injects the matched rule name into the denial response, which aids debugging and structured log queries.
- The same `acl` field is available for shared extensions under `spec.kube.sharedExtensions.<extension>` in `EnterpriseKgatewayParameters` — you can restrict access to ExtAuth or RateLimiter deployments the same way.
- **On Minikube**, use a `ListenerPolicy` with `useRemoteAddress: true` and `xffNumTrustedHops: 1` to evaluate XFF as the client IP. In production, the same setting honours the real client IP forwarded by the upstream load balancer.
