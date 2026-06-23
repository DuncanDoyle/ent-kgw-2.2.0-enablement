#!/bin/sh
# Inspect the contents of both Valkey caches to demonstrate that BYO Redis is working.
#
# valkey-auth      — ExtAuth OIDC sessions (one entry per logged-in browser session)
# valkey-ratelimit — RateLimiter counters (one entry per active rate-limit window)

printf "\n=== ExtAuth Session Cache (valkey-auth) ===\n"
SESSIONS=$(kubectl exec -n byo-redis deployment/valkey-auth -- valkey-cli keys '*' 2>/dev/null)
if [ -z "$SESSIONS" ]; then
  printf "  (empty — no active sessions; log in via the browser first)\n"
else
  printf "Active sessions:\n"
  echo "$SESSIONS" | while read -r key; do
    TTL=$(kubectl exec -n byo-redis deployment/valkey-auth -- valkey-cli ttl "$key" 2>/dev/null)
    SIZE=$(kubectl exec -n byo-redis deployment/valkey-auth -- valkey-cli strlen "$key" 2>/dev/null)
    printf "  • key : %s\n" "$key"
    printf "    TTL : %s seconds\n" "$TTL"
    printf "    size: %s bytes (gob-encoded)\n" "$SIZE"
    printf "    tokens:\n"

    # Retrieve raw session bytes as base64 (base64 -w0 disables line-wrap on GNU coreutils),
    # then pipe directly into Python. Using python3 -c avoids the heredoc-stdin conflict that
    # occurs when calling a shell function containing "python3 - <<EOF" inside a pipeline
    # (the heredoc consumes stdin before the script can read session data from it).
    kubectl exec -n byo-redis deployment/valkey-auth -- \
      sh -c "valkey-cli --raw get '${key}' | base64 -w0" 2>/dev/null \
    | python3 -c '
import sys, re, base64, json
from datetime import datetime, timezone

raw = sys.stdin.read().strip()
if not raw:
    print("      (could not read session data)")
    sys.exit(0)

# Decode the base64 shell output to recover the raw gob binary.
data = base64.b64decode(raw + "=" * (-len(raw) % 4))

# JWTs are stored as contiguous printable ASCII strings inside the gob binary.
# Extract all printable runs and keep the ones that look like JWTs (three dot-separated
# base64url segments starting with eyJ).
seen = set()
for run in re.findall(rb"[\x20-\x7e]{10,}", data):
    s = run.decode("ascii")
    parts = s.split(".")
    if len(parts) != 3 or not s.startswith("eyJ"):
        continue
    if s in seen:
        continue
    seen.add(s)

    try:
        payload_b64 = parts[1] + "=" * (-len(parts[1]) % 4)
        payload = json.loads(base64.urlsafe_b64decode(payload_b64))
    except Exception:
        continue

    # Keycloak token type conventions: payload.typ == "Bearer" → access token,
    # "Refresh" → refresh token; ID tokens have no typ but have at_hash.
    typ = payload.get("typ", "")
    if typ == "Bearer":
        label = "Access Token"
    elif typ == "Refresh":
        label = "Refresh Token"
    elif "at_hash" in payload:
        label = "ID Token"
    else:
        label = "Token (typ=" + (typ or "unknown") + ")"

    print("      [" + label + "]")
    for k in ("sub", "preferred_username", "email", "scope", "typ", "exp", "iat"):
        if k not in payload:
            continue
        v = payload[k]
        if k in ("exp", "iat"):
            try:
                ts = datetime.fromtimestamp(v, tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
                v = str(v) + "  (" + ts + ")"
            except Exception:
                pass
        print("        " + k + ": " + str(v))
'
  done
fi

printf "\n\n=== RateLimit Counter Cache (valkey-ratelimit) ===\n"
COUNTERS=$(kubectl exec -n byo-redis deployment/valkey-ratelimit -- valkey-cli keys '*' 2>/dev/null)
if [ -z "$COUNTERS" ]; then
  printf "  (empty — no requests counted yet; make some requests via the browser first)\n"
else
  printf "Active counters:\n"
  echo "$COUNTERS" | while read -r key; do
    VALUE=$(kubectl exec -n byo-redis deployment/valkey-ratelimit -- valkey-cli get "$key" 2>/dev/null)
    TTL=$(kubectl exec -n byo-redis deployment/valkey-ratelimit -- valkey-cli ttl "$key" 2>/dev/null)
    printf "  • key     : %s\n" "$key"
    printf "    requests: %s\n" "$VALUE"
    printf "    TTL     : %s seconds until counter resets\n" "$TTL"
  done
fi
