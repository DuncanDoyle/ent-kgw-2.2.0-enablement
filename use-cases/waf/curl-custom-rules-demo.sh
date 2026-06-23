#!/bin/sh
# Custom WAF rules demo — shows ConfigMap-based rules with request body inspection.
#
# Rules are stored in a ConfigMap (custom-waf-rules) so they can be updated without
# redeploying the WAFPolicy. The WAF server picks up ConfigMap changes automatically.
#
# Body inspection is enabled via processingConfig.request.mode: HeadersAndBody,
# which allows phase:2 rules to inspect the full JSON request body.

GW_IP=${GW_IP:-$(kubectl get gateway gw -n waf -o jsonpath='{.status.addresses[0].value}')}

if [ -z "$GW_IP" ]; then
  echo "Could not determine GW_IP. Is the gateway deployed and does it have an address?"
  exit 1
fi

GW_PORT=8080
HOST="custom-rules.example.com"

# ---------------------------------------------------------------------------
# 1. POST with a clean body — no blocked pattern. Expect 200.
# ---------------------------------------------------------------------------
printf "\n=== POST with clean body (expect 200) ===\n"
curl -si "http://${GW_IP}:${GW_PORT}/post" \
  -H "host: ${HOST}" \
  -H "Content-Type: application/json" \
  -d '{"secret": "my-safe-value", "message": "hello"}'

# ---------------------------------------------------------------------------
# 2. POST containing the blocked pattern in the 'secret' field. Expect 403.
# The WAFPolicy inspects the full JSON body (HeadersAndBody mode) and matches
# rule id:3002 against ARGS:json.secret.
# ---------------------------------------------------------------------------
printf "\n\n=== POST with blocked secret pattern (expect 403) ===\n"
curl -si "http://${GW_IP}:${GW_PORT}/post" \
  -H "host: ${HOST}" \
  -H "Content-Type: application/json" \
  -d '{"secret": "leaked-secret", "message": "this should be blocked"}'

# ---------------------------------------------------------------------------
# 3. Demonstrate hot-reload: update the ConfigMap to change the blocked pattern,
# then show the previously blocked request now passes and a new one is blocked.
# ---------------------------------------------------------------------------
printf "\n\n=== Hot-reload demo ===\n"
printf "Patching ConfigMap to block 'new-blocked-pattern' instead of 'leaked-secret' ...\n"

kubectl patch configmap custom-waf-rules -n waf --type merge -p '
{
  "data": {
    "custom-rules.conf": "SecRule REQUEST_HEADERS:Content-Type \"@rx ^application/json\" \"id:3001,phase:1,pass,nolog,ctl:requestBodyProcessor=JSON\"\nSecRule ARGS:json.secret \"@contains new-blocked-pattern\" \"id:3002,phase:2,deny,status:403,msg:'\''Sensitive data pattern detected in request body'\''\"\n"
  }
}'

printf "Waiting 5s for the WAF server to pick up the new rules ...\n"
sleep 5

printf "\nPreviously blocked request (expect 200 now) ...\n"
curl -si "http://${GW_IP}:${GW_PORT}/post" \
  -H "host: ${HOST}" \
  -H "Content-Type: application/json" \
  -d '{"secret": "leaked-secret", "message": "should now pass"}'

printf "\n\nNew blocked pattern (expect 403) ...\n"
curl -si "http://${GW_IP}:${GW_PORT}/post" \
  -H "host: ${HOST}" \
  -H "Content-Type: application/json" \
  -d '{"secret": "new-blocked-pattern", "message": "should be blocked"}'

# Restore the original ConfigMap so teardown is clean.
printf "\n\nRestoring original ConfigMap ...\n"
kubectl apply -f configmaps/custom-rules-cm.yaml
