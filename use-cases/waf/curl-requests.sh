#!/bin/sh
# WAF demo — curl requests showing what the WAF blocks and what it passes.

GW_IP=${GW_IP:-$(kubectl get gateway gw -n waf -o jsonpath='{.status.addresses[0].value}')}

if [ -z "$GW_IP" ]; then
  echo "Could not determine GW_IP. Is the gateway deployed and does it have an address?"
  exit 1
fi
GW_PORT=8080
HOST="waf.example.com"

# ---------------------------------------------------------------------------
# 1. Normal request — should return 200.
# ---------------------------------------------------------------------------
printf "\n=== Normal request (expect 200) ===\n"
curl -si "http://${GW_IP}:${GW_PORT}/get" -H "host: ${HOST}"

# ---------------------------------------------------------------------------
# 2. Local File Inclusion (LFI) — CRS rule 930130 blocks access to .htaccess.
# Phase 1 (request headers): path matched against restricted file list.
# ---------------------------------------------------------------------------
printf "\n=== LFI: access .htaccess (expect 403) ===\n"
curl -si "http://${GW_IP}:${GW_PORT}/.htaccess" -H "host: ${HOST}"

# ---------------------------------------------------------------------------
# 3. SQL injection in query string — CRS 942xxx rules (Phase 1).
# ---------------------------------------------------------------------------
printf "\n=== SQL injection in query string (expect 403) ===\n"
curl -si "http://${GW_IP}:${GW_PORT}/get?id=1%27%20OR%20%271%27%3D%271" \
  -H "host: ${HOST}"

# ---------------------------------------------------------------------------
# 4. XSS in query string — CRS 941xxx rules (Phase 1).
# ---------------------------------------------------------------------------
printf "\n=== XSS in query string (expect 403) ===\n"
curl -si "http://${GW_IP}:${GW_PORT}/get?q=%3Cscript%3Ealert(1)%3C%2Fscript%3E" \
  -H "host: ${HOST}"

# ---------------------------------------------------------------------------
# 5. Custom User-Agent rule — blocked by the custom Coraza rule (id:5001),
# not by CRS. Demonstrates layering custom rules on top of the rule set.
# ---------------------------------------------------------------------------
printf "\n=== Custom User-Agent block (expect 403) ===\n"
curl -si "http://${GW_IP}:${GW_PORT}/get" \
  -H "host: ${HOST}" \
  -H "User-Agent: bad-bot"

# ---------------------------------------------------------------------------
# 6. Check the WAF server logs to see blocked request details.
# ---------------------------------------------------------------------------
printf "\n=== WAF server logs (last 20 lines) ===\n"
kubectl logs -n kgateway-system deploy/waf-server-enterprise-kgateway-waf --tail=20
