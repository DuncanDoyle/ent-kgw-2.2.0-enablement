#!/bin/sh

pushd ..

# ---------------------------------------------------------------------------
# Step 1: Create a dedicated EnterpriseKgatewayParameters with WAF enabled and
# a matching GatewayClass. Any Gateway that uses enterprise-kgateway-waf gets
# its own WAF server; gateways on the original enterprise-kgateway class are
# unaffected.
# ---------------------------------------------------------------------------
printf "\nDeploy EnterpriseKgatewayParameters (WAF) ...\n"
kubectl apply -f gateways/ent-kgateway-waf-params.yaml

printf "\nDeploy GatewayClass enterprise-kgateway-waf ...\n"
kubectl apply -f gateways/enterprise-kgateway-waf.yaml

# Wait for the WAF server that is spun up for the new GatewayClass.
printf "\nWaiting for waf-server to be ready ...\n"
kubectl rollout status deploy -n kgateway-system -l app.kubernetes.io/name=waf-server --timeout=120s

# ---------------------------------------------------------------------------
# Step 2: Create namespaces.
# ---------------------------------------------------------------------------
printf "\nCreate namespaces ...\n"
kubectl create namespace waf --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace waf-httpbin --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# Step 3: Deploy the Gateway (uses enterprise-kgateway-waf GatewayClass).
# ---------------------------------------------------------------------------
printf "\nDeploy Gateway ...\n"
kubectl apply -f gateways/gw.yaml

printf "\nDeploy ListenerPolicy (XFF trust for IP filtering) ...\n"
kubectl apply -f gateways/listener-policy.yaml

# ---------------------------------------------------------------------------
# Step 4: Deploy the httpbin backend application.
# ---------------------------------------------------------------------------
printf "\nDeploy httpbin application ...\n"
kubectl apply -f apis/httpbin/httpbin.yaml

# ---------------------------------------------------------------------------
# Step 5: Deploy ReferenceGrant to allow the HTTPRoute in the waf namespace
# to reference the httpbin Service in the waf-httpbin namespace.
# ---------------------------------------------------------------------------
printf "\nDeploy ReferenceGrant ...\n"
kubectl apply -f referencegrants/waf-httpbin/httproute-waf-service-rg.yaml

# ---------------------------------------------------------------------------
# Step 6: Deploy the HTTPRoute.
# ---------------------------------------------------------------------------
printf "\nDeploy HTTPRoute ...\n"
kubectl apply -f routes/httpbin-httproute.yaml

# ---------------------------------------------------------------------------
# Step 7: Deploy WAFPolicy (OWASP CRS + custom rules) and attach it to the
# HTTPRoute via an EnterpriseKgatewayTrafficPolicy.
# ---------------------------------------------------------------------------
printf "\nDeploy WAFPolicy (OWASP CRS) ...\n"
kubectl apply -f policies/waf-policy.yaml

printf "\nDeploy EnterpriseKgatewayTrafficPolicy (OWASP CRS) ...\n"
kubectl apply -f policies/traffic-policy.yaml

# ---------------------------------------------------------------------------
# Step 8: Deploy the IP filtering route, WAFPolicy, and TrafficPolicy.
# ---------------------------------------------------------------------------
printf "\nDeploy HTTPRoute for IP filtering demo ...\n"
kubectl apply -f routes/ip-filter-httproute.yaml

printf "\nDeploy WAFPolicy (IP filtering) ...\n"
kubectl apply -f policies/ip-filter-waf-policy.yaml

printf "\nDeploy EnterpriseKgatewayTrafficPolicy (IP filtering) ...\n"
kubectl apply -f policies/ip-filter-traffic-policy.yaml

# ---------------------------------------------------------------------------
# Step 9: Deploy the custom rules demo (ConfigMap-based rules + body inspection).
# ---------------------------------------------------------------------------
printf "\nDeploy ConfigMap with custom WAF rules ...\n"
kubectl apply -f configmaps/custom-rules-cm.yaml

printf "\nDeploy HTTPRoute for custom rules demo ...\n"
kubectl apply -f routes/custom-rules-httproute.yaml

printf "\nDeploy WAFPolicy (custom rules) ...\n"
kubectl apply -f policies/custom-rules-waf-policy.yaml

printf "\nDeploy EnterpriseKgatewayTrafficPolicy (custom rules) ...\n"
kubectl apply -f policies/custom-rules-traffic-policy.yaml

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
printf "\nWaiting for Gateway to be programmed ...\n"
kubectl wait gateway/gw -n waf --for=condition=Programmed --timeout=120s

printf "\nGateway address:\n"
kubectl get gateway gw -n waf

printf "\nWAFPolicy status:\n"
kubectl get wafpolicy httpbin-waf -n waf

popd
