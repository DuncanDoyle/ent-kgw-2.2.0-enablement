# Solo Enterprise for kgateway — Enablement Demo

This repository demonstrates Solo Enterprise for kgateway 2.2.x running on Minikube with MetalLB. It consists of a base installation that installs and configures the gateway, and a set of independent use-cases that each demonstrate a specific feature.

## Base Setup

The base setup installs Solo Enterprise for kgateway and configures a minimal environment shared by the base demo.

### 1. Install Solo Enterprise for kgateway

```sh
cd install
./install-ent-kgw-with-helm.sh
```

> The version to install is set as a variable at the top of `install/install-ent-kgw-with-helm.sh`.

### 2. Set up the base environment

```sh
./setup.sh
```

This script:
- Creates the required namespaces
- Deploys the Gateway
- Deploys the ReferenceGrants
- Deploys the HTTPBin application
- Deploys the HTTPRoute (Kubernetes Gateway API)

### 3. Verify the base installation

```sh
./curl-request-g8s-gw-api.sh
```

or directly:

```sh
curl -v http://api.example.com/get
```

## Use-Cases

Each use-case lives in its own directory under `use-cases/` and can be set up and torn down independently. They do not depend on each other — you can run any subset in any order.

| Use-Case | Directory | What it demonstrates |
|---|---|---|
| Gateway API 1.5.1 | `use-cases/gateway-api-1.5.1` | Gateway API 1.5.1 features: mTLS, `AllowInsecureFallback`, per-port TLS configuration |
| BYO Redis | `use-cases/byo-redis` | Bring-your-own Redis (Valkey) for ExtAuth session storage and RateLimiter — replaces the default in-memory store |
| WAF | `use-cases/waf` | Web Application Firewall: OWASP CRS, custom rules, IP filtering via WAF rules, request body inspection |
| Overlays | `use-cases/overlays` | Native vs overlay customization of managed proxy resources: resource limits, HPA, PDB, init containers, debug sidecar |
| ACL | `use-cases/acl` | IP-based access control: allowlist, denylist, and hole-punching via longest-prefix matching |

### Running a use-case

Each use-case directory contains:
- `install/setup.sh` — deploys all resources for that use-case
- `install/teardown.sh` — removes all resources for that use-case
- A README with configuration details and a demo walkthrough
- One or more `curl-*.sh` scripts to exercise the feature

Example:

```sh
cd use-cases/acl
sh install/setup.sh
sh curl-acl-demo.sh
sh install/teardown.sh
```

Use-cases create their own namespaces and GatewayClass, so they are isolated from the base setup and from each other.
