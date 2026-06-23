#!/bin/sh
# ACL demo — shows all three ACL patterns: allowlist, denylist, and hole-punching.
#
# The ListenerPolicy configures Envoy to trust the X-Forwarded-For header as the
# client IP. This lets us forge -H "X-Forwarded-For: <ip>" to simulate requests
# from any address without needing actual clients at those IPs.
#
# ACL uses longest-prefix matching: a /32 rule beats a /16 rule for the same IP
# regardless of the order rules are listed in the policy.

GW_IP=${GW_IP:-$(kubectl get gateway gw -n acl -o jsonpath='{.status.addresses[0].value}')}

if [ -z "$GW_IP" ]; then
  printf "Could not determine GW_IP. Is the gateway deployed?\n"
  exit 1
fi

HOST="acl.example.com"

# ---------------------------------------------------------------------------
# Baseline — no ACL policy on this route. Any IP gets through.
# ---------------------------------------------------------------------------
printf "\n================================================================\n"
printf " Baseline — no ACL policy (/get)\n"
printf "================================================================\n"

printf "\n--- Any IP, expect 200 ---\n"
curl -si "http://${GW_IP}/get" -H "host: ${HOST}" -H "X-Forwarded-For: 10.10.0.1" \
  | head -1

printf "\n--- Any IP, expect 200 ---\n"
curl -si "http://${GW_IP}/get" -H "host: ${HOST}" -H "X-Forwarded-For: 1.2.3.4" \
  | head -1

# ---------------------------------------------------------------------------
# Allowlist — defaultAction: deny, allow 10.10.0.0/16 only.
# ---------------------------------------------------------------------------
printf "\n================================================================\n"
printf " Allowlist — allow 10.10.0.0/16, deny everything else (/headers)\n"
printf "================================================================\n"
printf "Policy: defaultAction=deny, rule allow-internal: 10.10.0.0/16 → allow\n"

printf "\n--- 10.10.0.1 (in allowed /16), expect 200 ---\n"
curl -si "http://${GW_IP}/headers" -H "host: ${HOST}" -H "X-Forwarded-For: 10.10.0.1" \
  | head -1

printf "\n--- 10.10.99.99 (in allowed /16), expect 200 ---\n"
curl -si "http://${GW_IP}/headers" -H "host: ${HOST}" -H "X-Forwarded-For: 10.10.99.99" \
  | head -1

printf "\n--- 192.168.1.1 (not in allowed /16), expect 403 + X-Blocked-By: default ---\n"
curl -si "http://${GW_IP}/headers" -H "host: ${HOST}" -H "X-Forwarded-For: 192.168.1.1" \
  | grep -E "^HTTP|X-Blocked-By"

printf "\n--- 1.2.3.4 (not in allowed /16), expect 403 + X-Blocked-By: default ---\n"
curl -si "http://${GW_IP}/headers" -H "host: ${HOST}" -H "X-Forwarded-For: 1.2.3.4" \
  | grep -E "^HTTP|X-Blocked-By"

# ---------------------------------------------------------------------------
# Denylist — defaultAction: allow, deny 10.10.0.0/16.
# ---------------------------------------------------------------------------
printf "\n================================================================\n"
printf " Denylist — deny 10.10.0.0/16, allow everything else (/anything)\n"
printf "================================================================\n"
printf "Policy: defaultAction=allow, rule block-internal: 10.10.0.0/16 → deny\n"

printf "\n--- 10.10.0.1 (in blocked /16), expect 403 + X-Blocked-By: block-internal ---\n"
curl -si "http://${GW_IP}/anything" -H "host: ${HOST}" -H "X-Forwarded-For: 10.10.0.1" \
  | grep -E "^HTTP|X-Blocked-By"

printf "\n--- 10.10.99.99 (in blocked /16), expect 403 + X-Blocked-By: block-internal ---\n"
curl -si "http://${GW_IP}/anything" -H "host: ${HOST}" -H "X-Forwarded-For: 10.10.99.99" \
  | grep -E "^HTTP|X-Blocked-By"

printf "\n--- 192.168.1.1 (not in blocked /16), expect 200 ---\n"
curl -si "http://${GW_IP}/anything" -H "host: ${HOST}" -H "X-Forwarded-For: 192.168.1.1" \
  | head -1

printf "\n--- 1.2.3.4 (not in blocked /16), expect 200 ---\n"
curl -si "http://${GW_IP}/anything" -H "host: ${HOST}" -H "X-Forwarded-For: 1.2.3.4" \
  | head -1

# ---------------------------------------------------------------------------
# Hole-punching — deny 10.10.0.0/16, but allow 10.10.5.100/32 specifically.
#
# Longest-prefix matching: /32 > /16 regardless of rule order.
# 10.10.5.100 matches both the /16 deny and the /32 allow. The /32 wins.
# ---------------------------------------------------------------------------
printf "\n================================================================\n"
printf " Hole-punching — /32 exception inside a blocked /16 (/uuid)\n"
printf "================================================================\n"
printf "Policy: defaultAction=allow\n"
printf "        rule block-subnet:  10.10.0.0/16 → deny\n"
printf "        rule allow-exception: 10.10.5.100/32 → allow  (overrides /16)\n"

printf "\n--- 10.10.1.1 (in blocked /16, no exception), expect 403 ---\n"
curl -si "http://${GW_IP}/uuid" -H "host: ${HOST}" -H "X-Forwarded-For: 10.10.1.1" \
  | grep -E "^HTTP|X-Blocked-By"

printf "\n--- 10.10.5.99 (in blocked /16, not the exception IP), expect 403 ---\n"
curl -si "http://${GW_IP}/uuid" -H "host: ${HOST}" -H "X-Forwarded-For: 10.10.5.99" \
  | grep -E "^HTTP|X-Blocked-By"

printf "\n--- 10.10.5.100 (/32 exception overrides /16 block), expect 200 ---\n"
curl -si "http://${GW_IP}/uuid" -H "host: ${HOST}" -H "X-Forwarded-For: 10.10.5.100" \
  | head -1

printf "\n--- 192.168.1.1 (not in any blocked range), expect 200 ---\n"
curl -si "http://${GW_IP}/uuid" -H "host: ${HOST}" -H "X-Forwarded-For: 192.168.1.1" \
  | head -1

printf "\n================================================================\n"
printf " Done.\n"
printf "================================================================\n\n"
