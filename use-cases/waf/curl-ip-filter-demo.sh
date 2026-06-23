#!/bin/sh
# IP filtering demo — shows WAF blocking requests from a specific IP address.
#
# The WAFPolicy (ip-filter-waf) blocks requests where X-Forwarded-For matches
# 1.2.3.4. In production behind a trusted load balancer you would use REMOTE_ADDR
# by configuring a ListenerPolicy with useRemoteAddress: true.

GW_IP=${GW_IP:-$(kubectl get gateway gw -n waf -o jsonpath='{.status.addresses[0].value}')}

if [ -z "$GW_IP" ]; then
  echo "Could not determine GW_IP. Is the gateway deployed and does it have an address?"
  exit 1
fi

GW_PORT=8080
HOST="ip-filter.example.com"

# ---------------------------------------------------------------------------
# 1. Normal request — no X-Forwarded-For header. Expect 200.
# ---------------------------------------------------------------------------
printf "\n=== Normal request — no blocked IP (expect 200) ===\n"
curl -si "http://${GW_IP}:${GW_PORT}/get" -H "host: ${HOST}"

# ---------------------------------------------------------------------------
# 2. Request from blocked IP — X-Forwarded-For: 1.2.3.4. Expect 403.
# ---------------------------------------------------------------------------
printf "\n=== Request from blocked IP 1.2.3.4 (expect 403) ===\n"
curl -si "http://${GW_IP}:${GW_PORT}/get" \
  -H "host: ${HOST}" \
  -H "X-Forwarded-For: 1.2.3.4"

# ---------------------------------------------------------------------------
# 3. Request from a different IP — not in the blocklist. Expect 200.
# ---------------------------------------------------------------------------
printf "\n=== Request from non-blocked IP 5.6.7.8 (expect 200) ===\n"
curl -si "http://${GW_IP}:${GW_PORT}/get" \
  -H "host: ${HOST}" \
  -H "X-Forwarded-For: 5.6.7.8"
