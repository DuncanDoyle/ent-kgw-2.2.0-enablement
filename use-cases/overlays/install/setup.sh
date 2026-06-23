#!/bin/sh

pushd ..

# ---------------------------------------------------------------------------
# Step 1: Create a dedicated EnterpriseKgatewayParameters with overlay
# customizations and a matching GatewayClass.
# ---------------------------------------------------------------------------
printf "\nDeploy EnterpriseKgatewayParameters (overlays) ...\n"
kubectl apply -f gateways/ent-kgateway-overlays-params.yaml

printf "\nDeploy GatewayClass enterprise-kgateway-overlays ...\n"
kubectl apply -f gateways/enterprise-kgateway-overlays.yaml

# ---------------------------------------------------------------------------
# Step 2: Create namespaces.
# ---------------------------------------------------------------------------
printf "\nCreate namespaces ...\n"
kubectl create namespace overlays --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace overlays-httpbin --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# Step 3: Deploy the httpbin backend application.
# ---------------------------------------------------------------------------
printf "\nDeploy httpbin application ...\n"
kubectl apply -f apis/httpbin/httpbin.yaml

# ---------------------------------------------------------------------------
# Step 4: Deploy the Gateway.
# The controller sees the Gateway, creates a proxy Deployment in the 'overlays'
# namespace, and applies all overlays from ent-kgateway-overlays-params.yaml.
# ---------------------------------------------------------------------------
printf "\nDeploy Gateway ...\n"
kubectl apply -f gateways/gw.yaml

# ---------------------------------------------------------------------------
# Step 5: Deploy ReferenceGrant and HTTPRoute.
# ---------------------------------------------------------------------------
printf "\nDeploy ReferenceGrant ...\n"
kubectl apply -f referencegrants/overlays-httpbin/httproute-overlays-service-rg.yaml

printf "\nDeploy HTTPRoute ...\n"
kubectl apply -f routes/httpbin-httproute.yaml

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
printf "\nWaiting for Gateway to be programmed ...\n"
kubectl wait gateway/gw -n overlays --for=condition=Programmed --timeout=120s

printf "\nWaiting for proxy pod to be ready (init container runs first) ...\n"
kubectl rollout status deploy -n overlays --timeout=120s 2>/dev/null || true

GW_IP=$(kubectl get gateway gw -n overlays -o jsonpath='{.status.addresses[0].value}')
printf "\nSetup complete.\n"
printf "Gateway IP: %s\n" "$GW_IP"
printf "\nAdd to /etc/hosts (if not already present):\n"
printf "  %s  httpbin.example.com\n" "$GW_IP"
printf "\nThen open http://httpbin.example.com/get in your browser.\n"
printf "\nRun:  sh show-overlays.sh\n"
printf "to inspect all overlay customizations applied to the managed resources.\n"

popd
