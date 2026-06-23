#!/bin/sh

pushd ..

# ---------------------------------------------------------------------------
# Step 1: Create a dedicated EnterpriseKgatewayParameters and GatewayClass.
# ACL is evaluated inline by the Envoy proxy — no external server is spun up.
# ---------------------------------------------------------------------------
printf "\nDeploy EnterpriseKgatewayParameters (ACL) ...\n"
kubectl apply -f gateways/ent-kgateway-acl-params.yaml

printf "\nDeploy GatewayClass enterprise-kgateway-acl ...\n"
kubectl apply -f gateways/enterprise-kgateway-acl.yaml

# ---------------------------------------------------------------------------
# Step 2: Create namespaces.
# ---------------------------------------------------------------------------
printf "\nCreate namespaces ...\n"
kubectl create namespace acl --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace acl-httpbin --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# Step 3: Deploy the httpbin backend.
# ---------------------------------------------------------------------------
printf "\nDeploy httpbin application ...\n"
kubectl apply -f apis/httpbin/httpbin.yaml

# ---------------------------------------------------------------------------
# Step 4: Deploy the Gateway and the ListenerPolicy that configures XFF trust.
# The ListenerPolicy makes Envoy evaluate the X-Forwarded-For header as the
# client IP, which is how the demo script simulates different source addresses.
# ---------------------------------------------------------------------------
printf "\nDeploy Gateway ...\n"
kubectl apply -f gateways/gw.yaml

printf "\nDeploy ListenerPolicy (XFF trust for ACL evaluation) ...\n"
kubectl apply -f gateways/listener-policy.yaml

# ---------------------------------------------------------------------------
# Step 5: Deploy the ReferenceGrant allowing HTTPRoutes in 'acl' to reference
# the httpbin Service in 'acl-httpbin'.
# ---------------------------------------------------------------------------
printf "\nDeploy ReferenceGrant ...\n"
kubectl apply -f referencegrants/acl-httpbin/httproute-acl-service-rg.yaml

# ---------------------------------------------------------------------------
# Step 6: Deploy the four HTTPRoutes (default, allowlist, denylist, holepunch).
# ---------------------------------------------------------------------------
printf "\nDeploy HTTPRoutes ...\n"
kubectl apply -f routes/httpbin-default-httproute.yaml
kubectl apply -f routes/httpbin-allowlist-httproute.yaml
kubectl apply -f routes/httpbin-denylist-httproute.yaml
kubectl apply -f routes/httpbin-holepunch-httproute.yaml

# ---------------------------------------------------------------------------
# Step 7: Deploy the three ACL TrafficPolicies.
# The default route has no policy — baseline to confirm routing works.
# ---------------------------------------------------------------------------
printf "\nDeploy ACL TrafficPolicies ...\n"
kubectl apply -f policies/allowlist-traffic-policy.yaml
kubectl apply -f policies/denylist-traffic-policy.yaml
kubectl apply -f policies/holepunch-traffic-policy.yaml

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
printf "\nWaiting for Gateway to be programmed ...\n"
kubectl wait gateway/gw -n acl --for=condition=Programmed --timeout=120s

printf "\nWaiting for proxy pod to be ready ...\n"
kubectl rollout status deploy -n acl --timeout=120s 2>/dev/null || true

GW_IP=$(kubectl get gateway gw -n acl -o jsonpath='{.status.addresses[0].value}')
printf "\nSetup complete.\n"
printf "Gateway IP: %s\n" "$GW_IP"
printf "\nRun:\n"
printf "  sh curl-acl-demo.sh\n"
printf "The demo script resolves the gateway IP automatically — no /etc/hosts entry needed.\n"

popd
