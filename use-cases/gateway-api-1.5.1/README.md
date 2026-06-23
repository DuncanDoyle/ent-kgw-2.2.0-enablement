# Gateway API 1.5.1 — ListenerSet, TLSRoute & mTLS

This use-case demonstrates three new capabilities introduced in **Kubernetes Gateway API 1.5.1** as supported by **Solo Enterprise for kgateway 2.2.x**:

- **ListenerSet** — attach additional listeners to a Gateway without modifying the Gateway resource itself
- **TLSRoute** — route TLS passthrough traffic to an external backend using SNI
- **mTLS client certificate validation** — enforce mutual TLS on a per-port basis via the `spec.tls.frontend` Gateway extension

## Architecture

```
                           ┌──────────────────────────────────────────────┐
                           │  Gateway gw (gwapi151)                        │
                           │  GatewayClass: enterprise-kgateway            │
                           │                                               │
                           │  Listeners (via ListenerSet):                 │
                           │  ┌─────────────────────────────────────────┐  │
                           │  │ http-api  HTTP :80  api.example.com     │  │
                           │  │ https-mtls HTTPS :443 mtls.example.com  │  │
                           │  │ tls        TLS Passthrough :6443        │  │
                           │  └─────────────────────────────────────────┘  │
                           └──────────────────────────────────────────────┘
                                     │             │              │
                          HTTPRoute  │    HTTPRoute│    TLSRoute  │
                       api.example.com  mtls.example.com    tcpbin.com
                                     │             │              │
                               ┌─────┘    ┌────────┘     ┌───────┘
                               ▼          ▼              ▼
                        httpbin (gwapi151-httpbin)   tcpbin.com:4243
                                                    (external, static Backend)
```

## Resources

| Resource | Kind | Namespace | Purpose |
|---|---|---|---|
| `gw` | Gateway | `gwapi151` | Entry point; owns mTLS frontend config |
| `gw-listenerset` | ListenerSet | `gwapi151` | Adds HTTP :80, HTTPS :443, TLS :6443 listeners |
| `api-example-com` | HTTPRoute | `gwapi151` | Routes `api.example.com` → httpbin (with CORS) |
| `mtls-example-com` | HTTPRoute | `gwapi151` | Routes `mtls.example.com` → httpbin (port 443, mTLS enforced) |
| `external-tcpbin` | TLSRoute | `gwapi151` | TLS passthrough → external `tcpbin.com` on port 6443 |
| `tcpbin-com` | Backend | `gwapi151` | Static external backend pointing at `tcpbin.com:4243` |
| `httpbin` | Deployment/Service | `gwapi151-httpbin` | Backend API for HTTP and mTLS routes |
| `gateway-server-tls` | Secret | `gwapi151` | Server TLS cert/key for the HTTPS listener |
| `client-ca` | ConfigMap | `gwapi151` | CA cert used to validate client certificates |

### ListenerSet

The ListenerSet binds to the `gw` Gateway and adds three listeners that are defined outside the Gateway resource itself. This allows teams to attach listeners to a shared gateway without requiring write access to the Gateway object.

```yaml
spec:
  parentRef:
    kind: Gateway
    name: gw
    namespace: gwapi151
  listeners:
    - name: http-api
      protocol: HTTP
      port: 80
      hostname: api.example.com
    - name: https-mtls
      protocol: HTTPS
      port: 443
      hostname: mtls.example.com
      tls:
        mode: Terminate
        certificateRefs:
          - name: gateway-server-tls
    - name: tls
      protocol: TLS
      port: 6443
      tls:
        mode: Passthrough
```

### mTLS Configuration

Client certificate validation is configured on the Gateway via `spec.tls.frontend`. The `default` mode is `AllowInsecureFallback` (no enforcement for listeners not matched by a `perPort` entry); port 443 is set to `AllowValidOnly`, which rejects any TLS handshake that does not present a cert signed by the `client-ca` CA.

```yaml
tls:
  frontend:
    default:
      validation:
        mode: AllowInsecureFallback       # No enforcement on HTTP/TLS listeners
        caCertificateRefs:
          - name: client-ca
            kind: ConfigMap
    perPort:
      - port: 443
        tls:
          validation:
            mode: AllowValidOnly          # Strict mTLS on port 443 only
            caCertificateRefs:
              - name: client-ca
                kind: ConfigMap
```

> **Note:** The `caCertificateRefs` field is required by the CRD schema even on the `default` entry used only as a fallback.

### TLSRoute

The TLSRoute routes TLS passthrough traffic to the external `tcpbin.com` service using SNI matching. The traffic is not terminated at the gateway — it is forwarded as-is to the backend on port 4243. The external host is defined as a `Backend` resource of type `Static`.

```yaml
spec:
  parentRefs:
    - kind: ListenerSet
      name: gw-listenerset
      sectionName: tls
  hostnames:
    - tcpbin.com
  rules:
    - backendRefs:
        - name: tcpbin-com
          kind: Backend
          group: gateway.kgateway.dev
```

## Setup

**Prerequisites:** Solo Enterprise for kgateway 2.2.x installed, `enterprise-kgateway` GatewayClass available, and Keycloak running (for the shared gateway installation).

```sh
cd use-cases/gateway-api-1.5.1
sh install/setup.sh
```

The setup script:
1. Creates namespaces `gwapi151` and `gwapi151-httpbin`
2. Generates a self-signed CA, server cert for `mtls.example.com`, and a client cert — stores them as a Secret and ConfigMap in `gwapi151` and writes the client material to `install/certs/`
3. Deploys the Gateway and ListenerSet
4. Deploys the httpbin backend and HTTPRoutes
5. Deploys the static Backend and TLSRoute for `tcpbin.com`

To tear down:

```sh
sh install/teardown.sh
```

## Running the Demo

### Get the Gateway IP

```sh
export GW_IP=$(kubectl get gateway gw -n gwapi151 -o jsonpath='{.status.addresses[0].value}')
echo $GW_IP
```

### 1. HTTP request via ListenerSet (`api.example.com`)

Demonstrates that the ListenerSet listener is active and routing works:

```sh
sh curl-request-k8s-gw-api.sh
```

Or manually:

```sh
curl -v --resolve "api.example.com:80:${GW_IP}" http://api.example.com/get
```

Expected result: `200 OK` with the httpbin `/get` JSON response.

### 2. mTLS demo (`mtls.example.com`)

Demonstrates port-443 client certificate enforcement:

```sh
sh curl-mtls-demo.sh
```

The script sends two requests:

**With a valid client cert** — the gateway validates the certificate against the CA and proxies the request. Expected: `200 OK`.

```sh
curl -s \
  --resolve "mtls.example.com:443:${GW_IP}" \
  --cacert install/certs/ca.crt \
  --cert   install/certs/client.crt \
  --key    install/certs/client.key \
  https://mtls.example.com:443/get
```

**Without a client cert** — the gateway rejects the TLS handshake because `AllowValidOnly` is enforced on port 443. Expected: TLS handshake failure.

```sh
curl -v \
  --resolve "mtls.example.com:443:${GW_IP}" \
  --cacert install/certs/ca.crt \
  https://mtls.example.com:443/get
```

### 3. TLS passthrough to tcpbin.com (port 6443)

Demonstrates TLSRoute: traffic is forwarded to `tcpbin.com:4243` with TLS intact (no termination at the gateway). `tcpbin.com` echoes back whatever is sent to it.

```sh
echo "hello from kgateway" | \
  openssl s_client -connect ${GW_IP}:6443 -servername tcpbin.com -quiet 2>/dev/null
```

Expected: the string echoed back from `tcpbin.com`.

## Key Learning Points

- **ListenerSet** lets you add listeners to a Gateway without editing the Gateway resource — useful for multi-team environments where gateway ownership is separate from route ownership.
- **TLSRoute** enables passthrough routing based on SNI, with the `Backend` CRD providing a way to reference external (out-of-cluster) hosts.
- **mTLS per-port** uses the `spec.tls.frontend.perPort` extension — scoped to port 443 — while leaving other listeners unaffected. The `default` mode must always be set even when only `perPort` is used.
- The `caCertificateRefs` can point to a **ConfigMap** (not just a Secret), which is the correct type for a public CA cert.
