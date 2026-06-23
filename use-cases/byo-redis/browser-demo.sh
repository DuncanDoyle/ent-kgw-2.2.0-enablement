#!/bin/sh
# Helper script for the BYO Redis browser demo.
# Resolves the gateway IP and checks /etc/hosts, then prints the demo steps.

GW_IP=$(kubectl get gateway gw -n byo-redis -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)

if [ -z "$GW_IP" ]; then
  echo "Could not determine GW_IP. Is the gateway deployed and does it have an address?"
  exit 1
fi

printf "\nGateway IP: %s\n" "$GW_IP"

# Check /etc/hosts
HOSTS_ENTRY=$(grep "httpbin.example.com" /etc/hosts 2>/dev/null || true)
printf "\n/etc/hosts check:\n"
if [ -n "$HOSTS_ENTRY" ]; then
  printf "  Found: %s\n" "$HOSTS_ENTRY"
  if ! echo "$HOSTS_ENTRY" | grep -q "$GW_IP"; then
    printf "  WARNING: entry exists but points to a different IP than %s — update it.\n" "$GW_IP"
  fi
else
  printf "  httpbin.example.com not found.\n"
  printf "  Add the following line to /etc/hosts (requires sudo):\n"
  printf "\n    %s  httpbin.example.com\n\n" "$GW_IP"
  printf "  Quick command:\n"
  printf "    sudo sh -c 'echo \"%s  httpbin.example.com\" >> /etc/hosts'\n" "$GW_IP"
fi

printf "\n============================================================\n"
printf " BYO Redis Demo — Browser Steps\n"
printf "============================================================\n"
printf "\n1. Open your browser and navigate to:\n"
printf "     http://httpbin.example.com/get\n"
printf "\n   You will be redirected to Keycloak to log in.\n"
printf "\n2. Log in with:\n"
printf "     Username : user1\n"
printf "     Password : password\n"
printf "\n3. After login, Keycloak redirects back to httpbin.\n"
printf "   The /get response shows the request headers — including the\n"
printf "   injected 'Id-Token' header from the OIDC flow.\n"
printf "\n4. Inspect the session cache:\n"
printf "     ./show-cache.sh\n"
printf "   You should see one session key in valkey-auth with a TTL of ~3600s.\n"
printf "\n5. Rate-limiting demo:\n"
printf "   Reload http://httpbin.example.com/get in the browser 3 more times.\n"
printf "   The 4th request within the same minute will return HTTP 429.\n"
printf "   Run ./show-cache.sh again to see the request counter in valkey-ratelimit.\n"
printf "\n6. Log out:\n"
printf "     http://httpbin.example.com/logout\n"
printf "   The session entry in valkey-auth will be removed.\n"
printf "\n============================================================\n"
