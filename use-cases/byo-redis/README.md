# Bring Your Own Redis (BYO Redis)

This use-case demonstrates how **Solo Enterprise for kgateway 2.2.x** supports customer-supplied Redis instances for both ExtAuth session storage and RateLimiter counters, replacing the bundled `ext-cache` Redis sidecar.

The demo combines three capabilities in a single, browser-friendly flow:

- **BYO Redis** — two separate Valkey 8 instances, one per component
- **OIDC Authentication** — authorization code flow via Keycloak; tokens stored in Redis, not in the browser cookie
- **Global Rate Limiting** — 3 requests per minute; counters stored in the dedicated rate-limit Redis

## Architecture

```
Browser
  │
  │  http://httpbin.example.com
  ▼
┌──────────────────────────────────────────────────────┐
│  Gateway gw (byo-redis, port 80)                      │
│  GatewayClass: enterprise-kgateway-byo-redis          │
│                                                       │
│  EnterpriseKgatewayParameters:                       │
│    extCache.enabled: false         ← no bundled Redis │
│    extauth.sessionRedis → valkey-auth:6379            │
│    ratelimiter.redis   → valkey-ratelimit:6379        │
└──────────────────────────────────────────────────────┘
  │
  │  HTTPRoute httpbin → httpbin.example.com
  │
  ├─→ EnterpriseKgatewayTrafficPolicy
  │     entExtAuth → AuthConfig (httpbin-oidc)
  │     entRateLimit → RateLimitConfig (httpbin-ratelimit)
  │
  ├─→ ExtAuth (extauth-enterprise-kgateway-byo-redis)
  │     OIDC Authorization Code Flow
  │     Session stored in ──────────────────────────────┐
  │                                                     ▼
  │                                              valkey-auth (byo-redis)
  │
  ├─→ RateLimiter (ratelimiter-enterprise-kgateway-byo-redis)
  │     3 req/min global counter stored in ────────────┐
  │                                                    ▼
  │                                             valkey-ratelimit (byo-redis)
  │
  └─→ httpbin (byo-redis-httpbin)
```

## Resources

| Resource | Kind | Namespace | Purpose |
|---|---|---|---|
| `ent-kgateway-byo-redis-params` | EnterpriseKgatewayParameters | `kgateway-system` | Disables ext-cache; points ExtAuth and RateLimiter at Valkey |
| `enterprise-kgateway-byo-redis` | GatewayClass | cluster-scoped | Points at `ent-kgateway-byo-redis-params` |
| `gw` | Gateway | `byo-redis` | Listens on port 80 |
| `valkey-auth` | Deployment/Service | `byo-redis` | Valkey 8 for ExtAuth OIDC session storage |
| `valkey-ratelimit` | Deployment/Service | `byo-redis` | Valkey 8 for RateLimiter counters |
| `httpbin` | HTTPRoute | `byo-redis` | Routes `httpbin.example.com` to httpbin |
| `httpbin-oidc` | AuthConfig | `byo-redis` | OIDC authorization code flow; Redis session config |
| `oauth` | Secret | `byo-redis` | Keycloak `httpbin-client` secret (created by setup) |
| `httpbin-ratelimit` | RateLimitConfig | `byo-redis` | 3 req/min global counter |
| `httpbin-byo-redis` | EnterpriseKgatewayTrafficPolicy | `byo-redis` | Attaches ExtAuth + RateLimit to the httpbin HTTPRoute |
| `httpbin` | Deployment/Service | `byo-redis-httpbin` | Backend API |

## EnterpriseKgatewayParameters

The parameters resource is the core of this demo. It explicitly disables the bundled ext-cache sidecar and points each component at a dedicated Valkey instance:

```yaml
spec:
  kube:
    sharedExtensions:
      extCache:
        enabled: false                                 # No bundled Redis sidecar
      waf:
        enabled: false
      ratelimiter:
        enabled: true
        redis:
          address: valkey-ratelimit.byo-redis.svc.cluster.local:6379
      extauth:
        enabled: true
        sessionRedis:
          address: valkey-auth.byo-redis.svc.cluster.local:6379
```

> **Two separate instances:** `valkey-auth` stores ExtAuth OIDC sessions; `valkey-ratelimit` stores RateLimiter counters. This mirrors a production pattern where the two stores have different scaling and eviction requirements.

### Production Redis options

The `ent-kgateway-byo-redis-params.yaml` file contains commented-out blocks showing the full set of Redis connection options supported for both `ratelimiter.redis` and `extauth.sessionRedis`:

**Connection tuning**
```yaml
connection:
  poolSize: 10
  minIdleConns: 2
  maxIdleConns: 5
  dialTimeout: 5s
```

**TLS**
```yaml
socketType: tls
certs:
  caCertSecretRef:
    name: redis-tls
    namespace: kgateway-system
  caCertKey: ca.crt
```

**Authentication — username/password**
```yaml
auth:
  secretRef:
    name: redis-credentials
    passwordKey: "redis-password"
    usernameKey: "redis-username"
```

**Authentication — AWS ElastiCache / MemoryDB**
```yaml
auth:
  aws:
    region: "${AWS_REGION}"
    clusterName: "${CACHE_NAME}"
    userName: "${DATABASE_USER}"
    serverlessCacheName: "${CACHE_NAME}"   # Required for ElastiCache Serverless only
```

All of these options apply identically to both `ratelimiter.redis` and `extauth.sessionRedis`.

## AuthConfig — OIDC Session in Redis

The AuthConfig configures the OIDC authorization code flow pointing at the `kgateway-demo` Keycloak realm. The `session.redis` block instructs ExtAuth to store the full token in Valkey and send only a session ID cookie to the browser:

```yaml
session:
  cookieOptions:
    notSecure: true       # Required for plain HTTP demo
    maxAge: 3600
  failOnFetchFailure: true
  redis:
    cookieName: httpbin-session
    options:
      host: valkey-auth.byo-redis.svc.cluster.local:6379
```

> **Note:** The Redis `host` for session storage is controlled at the server level by `EnterpriseKgatewayParameters.extauth.sessionRedis.address` — AuthConfigs inherit it automatically. The `session.redis.options.host` in the AuthConfig is redundant when it matches the server-level address; per-AuthConfig overrides are limited to `db`, `poolSize`, and `socketType`. Credentials and host can only be set at the server level.

## Keycloak Setup

The `kgateway-demo` Keycloak realm is created by `install/keycloak-realm.sh`. It is kept separate from the `gloo-demo` realm used by the shared gateway demos.

| Setting | Value |
|---|---|
| Realm | `kgateway-demo` |
| Client | `httpbin-client` |
| Redirect URI | `http://httpbin.example.com/*` |
| Demo user | `user1` / `password` |
| Issuer URL | `http://keycloak.example.com/realms/kgateway-demo/` |

The script creates the realm, registers the client, sets redirect URIs, creates the user, and stores the generated client secret as a Kubernetes Secret named `oauth` in the `byo-redis` namespace.

## Setup

**Prerequisites:** Solo Enterprise for kgateway 2.2.x installed and Keycloak running at `keycloak.example.com` (deployed by the shared `install/` setup). The environment variables `KEYCLOAK_HOST` and `KC_ADMIN_PASS` from `install/env.sh` must be set.

```sh
cd use-cases/byo-redis
sh install/setup.sh
```

The setup script:
1. Deploys `EnterpriseKgatewayParameters` and the `enterprise-kgateway-byo-redis` GatewayClass
2. Creates namespaces `byo-redis` and `byo-redis-httpbin`
3. Deploys both Valkey instances and waits for them to be ready
4. Deploys the Gateway, httpbin backend, ReferenceGrant, and HTTPRoute
5. Runs `keycloak-realm.sh` to create the Keycloak realm and store the client secret
6. Deploys the AuthConfig, RateLimitConfig, and TrafficPolicy
7. Verifies that no `ext-cache` pod is running (expected)

To tear down:

```sh
sh install/teardown.sh
```

## Running the Demo

### 1. Check /etc/hosts and get the Gateway IP

```sh
sh browser-demo.sh
```

The script resolves the Gateway IP and checks whether `httpbin.example.com` is in `/etc/hosts`. If not, it prints the entry to add:

```
<GW_IP>  httpbin.example.com
```

Add it with:
```sh
sudo sh -c 'echo "<GW_IP>  httpbin.example.com" >> /etc/hosts'
```

### 2. OIDC Login

Open a browser and navigate to `http://httpbin.example.com/get`.

You will be redirected to Keycloak. Log in with:
- **Username:** `user1`
- **Password:** `password`

After login, Keycloak redirects back to httpbin. The `/get` response shows the request headers, including the `Id-Token` and `Access-Token` headers injected by ExtAuth.

### 3. Inspect the Session Cache

```sh
sh show-cache.sh
```

Shows the contents of both Valkey instances:

- **`valkey-auth`** — one session key per logged-in browser session, with TTL ≈ 3600 seconds
- **`valkey-ratelimit`** — one counter key per active rate-limit window, counting requests

### 4. Rate Limiting

Reload `http://httpbin.example.com/get` in the browser more than 3 times within the same minute. The 4th request returns `429 Too Many Requests`.

Run `sh show-cache.sh` again to see the counter value incrementing in `valkey-ratelimit`.

### 5. Log Out

Navigate to `http://httpbin.example.com/logout`. The Keycloak session is terminated and the session entry is removed from `valkey-auth`. Run `sh show-cache.sh` to confirm.

### 6. Verify ext-cache is NOT Running

```sh
kubectl get pods -n kgateway-system | grep byo-redis
```

You should see ExtAuth and RateLimiter pods for `enterprise-kgateway-byo-redis`, but **no** `ext-cache` pod — confirming the bundled Redis sidecar is disabled.

## Key Learning Points

- `extCache.enabled: false` in `EnterpriseKgatewayParameters` disables the bundled Redis sidecar. ExtAuth and RateLimiter still work when their respective BYO Redis addresses are configured.
- The two Valkey instances use different field paths: `ratelimiter.redis.address` vs `extauth.sessionRedis.address` — they are independent and can point at different Redis clusters.
- OIDC session storage in Redis means the browser only holds a session ID cookie. The actual tokens (ID token, access token, refresh token) live in Valkey — they never leave the cluster.
- The rate limit counter key in `valkey-ratelimit` has a TTL that resets the window — watching the TTL in real time makes the sliding-window behavior visible.
