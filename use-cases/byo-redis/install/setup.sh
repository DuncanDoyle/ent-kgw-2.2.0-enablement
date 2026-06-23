#!/bin/sh

pushd ..

# ---------------------------------------------------------------------------
# Step 1: Create a dedicated EnterpriseKgatewayParameters with BYO Redis and
# a matching GatewayClass. extCache and WAF are explicitly disabled so the
# demo proves that ExtAuth and RateLimiter work without the bundled Redis sidecar.
# ---------------------------------------------------------------------------
printf "\nDeploy EnterpriseKgatewayParameters (BYO Redis) ...\n"
kubectl apply -f gateways/ent-kgateway-byo-redis-params.yaml

printf "\nDeploy GatewayClass enterprise-kgateway-byo-redis ...\n"
kubectl apply -f gateways/enterprise-kgateway-byo-redis.yaml

# ---------------------------------------------------------------------------
# Step 2: Create namespaces.
# ---------------------------------------------------------------------------
printf "\nCreate namespaces ...\n"
kubectl create namespace byo-redis --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace byo-redis-httpbin --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# Step 3: Deploy Valkey instances.
# Two separate instances: one for ExtAuth sessions, one for RateLimiter counters.
# ---------------------------------------------------------------------------
printf "\nDeploy Valkey instance for ExtAuth sessions (valkey-auth) ...\n"
kubectl apply -f redis/valkey-auth.yaml

printf "\nDeploy Valkey instance for RateLimiter counters (valkey-ratelimit) ...\n"
kubectl apply -f redis/valkey-ratelimit.yaml

printf "\nWaiting for Valkey deployments to be ready ...\n"
kubectl rollout status deploy/valkey-auth -n byo-redis --timeout=60s
kubectl rollout status deploy/valkey-ratelimit -n byo-redis --timeout=60s

# ---------------------------------------------------------------------------
# Step 4: Deploy the Gateway.
# ---------------------------------------------------------------------------
printf "\nDeploy Gateway ...\n"
kubectl apply -f gateways/gw.yaml

# ---------------------------------------------------------------------------
# Step 5: Deploy the httpbin backend application.
# ---------------------------------------------------------------------------
printf "\nDeploy httpbin application ...\n"
kubectl apply -f apis/httpbin/httpbin.yaml

# ---------------------------------------------------------------------------
# Step 6: Deploy ReferenceGrants.
# byo-redis-httpbin: allows the httpbin HTTPRoute to reference the httpbin Service.
# keycloak: allows the keycloak HTTPRoute to reference the Keycloak Service.
# ---------------------------------------------------------------------------
printf "\nDeploy ReferenceGrants ...\n"
kubectl apply -f referencegrants/byo-redis-httpbin/httproute-byo-redis-service-rg.yaml
kubectl apply -f referencegrants/keycloak/httproute-byo-redis-keycloak-rg.yaml

# ---------------------------------------------------------------------------
# Step 7: Deploy HTTPRoutes.
# ---------------------------------------------------------------------------
printf "\nDeploy HTTPRoute (httpbin) ...\n"
kubectl apply -f routes/httpbin-httproute.yaml

printf "\nDeploy HTTPRoute (keycloak) ...\n"
kubectl apply -f routes/keycloak-httproute.yaml

# ---------------------------------------------------------------------------
# Step 8: Set up Keycloak realm, client, and demo user.
# Creates the kgateway-demo realm with httpbin-client and user1/password,
# then stores the client secret as a K8s Secret in the byo-redis namespace.
# ---------------------------------------------------------------------------
printf "\nSet up Keycloak realm (kgateway-demo) ...\n"
bash install/keycloak-realm.sh

# ---------------------------------------------------------------------------
# Step 9: Deploy the AuthConfig (OIDC authorization code flow with Redis session).
# ---------------------------------------------------------------------------
printf "\nDeploy AuthConfig ...\n"
kubectl apply -f policies/authconfig.yaml

# ---------------------------------------------------------------------------
# Step 10: Deploy the RateLimitConfig (3 requests per minute, global counter).
# ---------------------------------------------------------------------------
printf "\nDeploy RateLimitConfig ...\n"
kubectl apply -f policies/ratelimit-config.yaml

# ---------------------------------------------------------------------------
# Step 11: Deploy the EnterpriseKgatewayTrafficPolicy (ExtAuth + RateLimit).
# ---------------------------------------------------------------------------
printf "\nDeploy EnterpriseKgatewayTrafficPolicy ...\n"
kubectl apply -f policies/traffic-policy.yaml

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
printf "\nWaiting for Gateway to be programmed ...\n"
kubectl wait gateway/gw -n byo-redis --for=condition=Programmed --timeout=120s

printf "\nGateway address:\n"
kubectl get gateway gw -n byo-redis

printf "\nVerifying ExtCache is NOT running for enterprise-kgateway-byo-redis ...\n"
if kubectl get pods -n kgateway-system -l "app=ext-cache-enterprise-kgateway-byo-redis" 2>/dev/null | grep -q "Running"; then
  printf "WARNING: An ext-cache pod is running — unexpected for BYO Redis setup.\n"
else
  printf "OK: No ext-cache pod running (as expected with extCache.enabled=false).\n"
fi

printf "\nExtAuth and RateLimiter pods for enterprise-kgateway-byo-redis:\n"
kubectl get pods -n kgateway-system | grep "enterprise-kgateway-byo-redis" || true

GW_IP=$(kubectl get gateway gw -n byo-redis -o jsonpath='{.status.addresses[0].value}')
printf "\nSetup complete.\n"
printf "Gateway IP: %s\n" "$GW_IP"
printf "\nAdd to /etc/hosts (if not already present):\n"
printf "  %s  httpbin.example.com\n" "$GW_IP"
printf "\nThen open http://httpbin.example.com/get in your browser.\n"
printf "Login with user1 / password via Keycloak.\n"

popd
