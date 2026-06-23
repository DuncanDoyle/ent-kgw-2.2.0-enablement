# Overlay Customizations

This use-case demonstrates the two complementary customization mechanisms in **Solo Enterprise for kgateway 2.2.x**:

1. **Native fields** in `EnterpriseKgatewayParameters` — typed, validated configuration that the control plane understands directly (resource limits, labels, annotations, node selector, affinity, HPA, PDB, etc.)
2. **Overlay fields** — strategic merge patches applied to the rendered Kubernetes resources for capabilities the native schema doesn't expose (init containers, sidecar injection, field removal, deep spec access)

Understanding when to use each is key to working effectively with the gateway.

## Native vs Overlay

```
Gateway API resource
        │
        ▼
  kgateway controller renders
  Deployment / Service / ServiceAccount
        │
        ├── Native fields translate directly
        │   (typed, validated, stable across versions)
        │
        └── Overlay fields merge after rendering
            (full Kubernetes schema, unvalidated, version-sensitive)
```

| Capability | Mechanism | Field |
|---|---|---|
| Resource limits on the proxy container | Native | `spec.kube.envoyContainer.resources` |
| Custom pod labels | Native | `spec.kube.podTemplate.extraLabels` |
| Custom pod annotations | Native | `spec.kube.podTemplate.extraAnnotations` |
| Node selector, affinity, tolerations | Native | `spec.kube.podTemplate.*` |
| Service type, ports, annotations | Native | `spec.kube.service.*` |
| Replica count, update strategy | Native | `spec.kube.deployment.*` |
| Security context removal | Native | `spec.kube.omitDefaultSecurityContext: true` |
| HPA (auto-scaling) | Native¹ | `spec.kube.horizontalPodAutoscaler` |
| PDB (disruption protection) | Native¹ | `spec.kube.podDisruptionBudget` |
| Init containers | **Overlay only** | `spec.kube.deploymentOverlay.initContainers` |
| Sidecar containers | **Overlay only** | `spec.kube.deploymentOverlay.containers` |
| Cloud LB spec fields (CIDR, static IP) | **Overlay only** | `spec.kube.serviceOverlay.spec` |
| IAM role binding (IRSA, GKE WI) | **Overlay only**² | `spec.kube.serviceAccountOverlay` |

¹ HPA and PDB generate standalone Kubernetes resources. The docs group them with overlay customizations because they extend the set of managed resources rather than patching existing ones, but they are first-class fields in `EnterpriseKgatewayParameters`, not strategic merge patches.

² Annotations can be set natively via `spec.kube.serviceAccount`; `serviceAccountOverlay` is used when you need to patch fields the native schema doesn't expose.

> **Overlay caveat:** Overlays are not validated by the control plane at apply time. A typo or wrong container name is silently accepted and only surfaces when Kubernetes processes the result. Test overlays after cluster upgrades — the underlying resource schema can change between Kubernetes versions.

## What This Demo Shows

### Native fields

- `envoyContainer.resources` → resource requests and limits on the proxy container
- `podTemplate.extraLabels` → `team=platform-engineering` label on proxy pods (usable for `kubectl get pods -l team=...`)
- `podTemplate.extraAnnotations` → Prometheus scrape annotations on the pod
- `horizontalPodAutoscaler` → HPA that scales the proxy between 1 and 3 replicas
- `podDisruptionBudget` → PDB ensuring at least one replica stays up

### Overlay fields (deploymentOverlay)

- `initContainers` → `preflight` init container that runs before the proxy starts, printing node/pod metadata via the Kubernetes Downward API
- `containers` → `debug-sidecar` that runs alongside the proxy, sharing its network namespace — allowing direct access to Envoy's local admin interface on `localhost:19000`

The debug sidecar is the most demonstrable overlay: `kubectl exec` into it and run `wget localhost:19000/ready` to prove it shares the proxy's loopback interface, something not achievable from outside the pod.

## Resources

| Resource | Kind | Namespace | Purpose |
|---|---|---|---|
| `ent-kgateway-overlays-params` | EnterpriseKgatewayParameters | `kgateway-system` | Native + overlay configuration for the proxy |
| `enterprise-kgateway-overlays` | GatewayClass | cluster-scoped | Points at `ent-kgateway-overlays-params` |
| `gw` | Gateway | `overlays` | Listens on port 80 |
| `httpbin` | HTTPRoute | `overlays` | Routes `httpbin.example.com` to httpbin |
| `httproute-overlays-httpbin` | ReferenceGrant | `overlays-httpbin` | Allows HTTPRoute to reference the httpbin Service |
| `httpbin` | Deployment/Service | `overlays-httpbin` | Backend API |

## Configuration

All customization lives in `gateways/ent-kgateway-overlays-params.yaml`.

### Native: envoyContainer and podTemplate

```yaml
spec:
  kube:
    envoyContainer:
      resources:
        requests:
          cpu: "100m"
          memory: "128Mi"
        limits:
          cpu: "500m"
          memory: "256Mi"
    podTemplate:
      extraLabels:
        team: platform-engineering
        environment: demo
      extraAnnotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "19000"
        prometheus.io/path: "/stats/prometheus"
```

### Native: HPA and PDB

```yaml
spec:
  kube:
    horizontalPodAutoscaler:
      spec:
        minReplicas: 1
        maxReplicas: 3
        metrics:
        - type: Resource
          resource:
            name: cpu
            target:
              type: Utilization
              averageUtilization: 80
    podDisruptionBudget:
      spec:
        minAvailable: 1
```

### Overlay: init container and debug sidecar

```yaml
spec:
  kube:
    deploymentOverlay:
      spec:
        template:
          spec:
            initContainers:
            - name: preflight
              image: busybox:stable
              command: [sh, -c, 'echo "[preflight] Init complete"']
            containers:
            # Adding a new container — no matching name in the rendered Deployment,
            # so strategic merge patch appends rather than merges.
            - name: debug-sidecar
              image: busybox:stable
              command: [sleep, infinity]
```

> **Container name merge key:** For `containers` entries, `name` is the strategic merge key. If the name matches an existing container (e.g., `kgateway`), the patch merges into that container. If the name is new (e.g., `debug-sidecar`), Kubernetes appends a new container. This is how you distinguish sidecar injection from patching the existing proxy container.

### Overlay: serviceOverlay and serviceAccountOverlay (commented out)

The params file contains commented-out examples for:
- **serviceOverlay** — cloud LB annotations (`aws-load-balancer-type`, `l4-rbs`), static IP, source IP CIDR filtering
- **serviceAccountOverlay** — AWS IRSA (`eks.amazonaws.com/role-arn`) and GKE Workload Identity annotations

These can be set natively for standard annotations; the overlay is only needed for spec-level changes not exposed by the native `service` or `serviceAccount` fields.

### Shared Extensions

All overlay fields also apply to ExtAuth, RateLimiter, and WAF under `spec.kube.sharedExtensions.<extension>`. Example:

```yaml
spec:
  kube:
    sharedExtensions:
      extauth:
        enabled: true
        deploymentOverlay:
          spec:
            template:
              spec:
                initContainers:
                - name: vault-agent
                  image: vault:latest
                  # fetch secrets before ext-auth starts
```

## Setup

**Prerequisites:** Solo Enterprise for kgateway 2.2.x installed.

```sh
cd use-cases/overlays
sh install/setup.sh
```

The setup script:
1. Deploys `EnterpriseKgatewayParameters` and the `enterprise-kgateway-overlays` GatewayClass
2. Creates namespaces `overlays` and `overlays-httpbin`
3. Deploys the httpbin backend
4. Deploys the Gateway — the controller creates the proxy Deployment and applies all customizations
5. Deploys the ReferenceGrant and HTTPRoute
6. Waits for the Gateway to be programmed (the `preflight` init container must complete before the pod reaches `Running`)

To tear down:

```sh
sh install/teardown.sh
```

## Running the Demo

### 1. Add the Gateway IP to /etc/hosts

```sh
GW_IP=$(kubectl get gateway gw -n overlays -o jsonpath='{.status.addresses[0].value}')
echo "$GW_IP  httpbin.example.com"
```

### 2. Verify routing works

Open `http://httpbin.example.com/get` in a browser. The httpbin JSON response confirms the gateway is running.

### 3. Inspect all customizations

```sh
sh show-overlays.sh
```

Expected output (trimmed):

```
================================================================
 Gateway Proxy Customizations — Effect Verification
================================================================

--- [Native] Custom Pod Labels (podTemplate.extraLabels) ---
NAME       READY   STATUS    LABELS
gw-xxx     1/1     Running   environment=demo,team=platform-engineering,...

--- [Native] Resource Limits (envoyContainer.resources) ---
  requests : cpu=100m  memory=128Mi
  limits   : cpu=500m  memory=256Mi

--- [Native] Prometheus Annotations (podTemplate.extraAnnotations) ---
  prometheus.io/path: /stats/prometheus
  prometheus.io/port: 19000
  prometheus.io/scrape: true

--- [Native] HorizontalPodAutoscaler ---
NAME   TARGETS   MINPODS   MAXPODS   REPLICAS
gw     0%/80%    1         3         1

--- [Native] PodDisruptionBudget ---
NAME   MIN AVAILABLE   ALLOWED DISRUPTIONS
gw     1               0

--- [Overlay] Init Container Output ---
[preflight] Overlay init container started
[preflight] Node : minikube
[preflight] Pod  : gw-xxx
[preflight] Time : 2026-06-23T09:00:00Z
[preflight] Init complete — proxy container may start

--- [Overlay] Debug Sidecar ---
Envoy readiness check via sidecar (wget localhost:19000/ready):

LIVE

Envoy cluster count via sidecar (wget localhost:19000/clusters):

xds_grpc::default_priority::max_connections::1024
...
```

### 4. Explore the debug sidecar

```sh
POD=$(kubectl get pods -n overlays -l team=platform-engineering -o jsonpath='{.items[0].metadata.name}')

# Sidecar shares localhost with the proxy — Envoy admin is reachable
kubectl exec -n overlays "$POD" -c debug-sidecar -- wget -qO- http://localhost:19000/ready

# List all Envoy clusters (xDS-configured upstreams)
kubectl exec -n overlays "$POD" -c debug-sidecar -- wget -qO- http://localhost:19000/clusters

# Check Envoy listener configuration
kubectl exec -n overlays "$POD" -c debug-sidecar -- wget -qO- http://localhost:19000/listeners
```

The sidecar can reach `localhost:19000` because containers in a pod share the same network namespace. This is not accessible from outside the pod — the admin interface is only exposed locally. A production use of this pattern would be a metrics exporter that scrapes `localhost:19000/stats/prometheus` and pushes to a remote Prometheus endpoint, or a log forwarder reading from a shared volume.

## Key Learning Points

- Many common customizations — resource limits, labels, annotations, node affinity, service config — are **native fields** in `EnterpriseKgatewayParameters`. Reach for overlays only when the native schema falls short.
- **HPA and PDB** generate standalone Kubernetes resources when their fields are present in `EnterpriseKgatewayParameters`. Removing the field deletes the resource. They are not strategic merge patches.
- The `deploymentOverlay` strategic merge patch uses **container name as the merge key**: a matching name patches the existing container; a new name adds a container. This is how init container injection and sidecar injection both work.
- A **sidecar injected via overlay** runs in the same network namespace as the proxy pod. It can reach `localhost:19000` (Envoy admin) even though that port is not exposed externally — enabling custom metric collection, log forwarding, or debugging without any network policy changes.
- The same overlay fields are available for shared extensions (`extauth`, `ratelimiter`, `waf`) under `spec.kube.sharedExtensions.<extension>`.
