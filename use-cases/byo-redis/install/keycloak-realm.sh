#!/bin/bash
# Creates the kgateway-demo Keycloak realm with a single OIDC client (httpbin-client)
# and a demo user (user1/password).
#
# Requires:
#   KEYCLOAK_HOST  — hostname for Keycloak (default: keycloak.example.com)
#   KC_ADMIN_PASS  — Keycloak master-realm admin password (default: admin)
#
# On success, stores the client secret as a Kubernetes Secret named 'oauth'
# in the byo-redis namespace.

set -e

KEYCLOAK_HOST="${KEYCLOAK_HOST:-keycloak.example.com}"
KC_ADMIN_PASS="${KC_ADMIN_PASS:-admin}"
KEYCLOAK_URL="http://${KEYCLOAK_HOST}"
REALM="kgateway-demo"
CLIENT_ID="httpbin-client"

echo "Keycloak URL : $KEYCLOAK_URL"
echo "Realm        : $REALM"
echo "Client       : $CLIENT_ID"

# ---------------------------------------------------------------------------
# Obtain admin token from the master realm.
# ---------------------------------------------------------------------------
KEYCLOAK_TOKEN=$(curl -sf \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=${KC_ADMIN_PASS}" \
  -d "grant_type=password" \
  "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" | jq -r .access_token)

[[ -z "$KEYCLOAK_TOKEN" || "$KEYCLOAK_TOKEN" == "null" ]] && \
  { echo "ERROR: Could not obtain Keycloak admin token. Check KEYCLOAK_HOST and KC_ADMIN_PASS."; exit 1; }

# ---------------------------------------------------------------------------
# Create realm (idempotent — ignore 409 conflict if it already exists).
# ---------------------------------------------------------------------------
printf "\nCreating realm '%s' ...\n" "$REALM"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"realm\": \"${REALM}\", \"enabled\": true}" \
  "${KEYCLOAK_URL}/admin/realms")

if [ "$STATUS" = "201" ]; then
  echo "Realm created."
elif [ "$STATUS" = "409" ]; then
  echo "Realm already exists — continuing."
else
  echo "ERROR: Unexpected status $STATUS when creating realm."; exit 1
fi

# ---------------------------------------------------------------------------
# Create httpbin-client via the admin API using the master-realm admin token.
# The client-registration endpoint requires a realm-scoped token, which does
# not work for a freshly created realm where the admin user does not exist.
# ---------------------------------------------------------------------------
printf "\nRegistering OIDC client '%s' ...\n" "$CLIENT_ID"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"clientId\": \"${CLIENT_ID}\",
    \"publicClient\": false,
    \"serviceAccountsEnabled\": false,
    \"directAccessGrantsEnabled\": true,
    \"standardFlowEnabled\": true,
    \"redirectUris\": [\"http://httpbin.example.com/*\"],
    \"webOrigins\": [\"*\"]
  }" \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/clients")

if [ "$STATUS" = "201" ]; then
  echo "Client created."
elif [ "$STATUS" = "409" ]; then
  echo "Client already exists — continuing."
else
  echo "ERROR: Unexpected status $STATUS when creating client."; exit 1
fi

# Look up the client's internal UUID and retrieve its generated secret.
REG_ID=$(curl -sf \
  -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=${CLIENT_ID}" | jq -r '.[0].id')

[[ -z "$REG_ID" || "$REG_ID" == "null" ]] && \
  { echo "ERROR: Could not look up client UUID for ${CLIENT_ID}."; exit 1; }

printf "Client UUID   : %s\n" "$REG_ID"

CLIENT_SECRET=$(curl -sf \
  -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${REG_ID}/client-secret" | jq -r '.value')

[[ -z "$CLIENT_SECRET" || "$CLIENT_SECRET" == "null" ]] && \
  { echo "ERROR: Could not retrieve client secret for ${CLIENT_ID}."; exit 1; }

# ---------------------------------------------------------------------------
# Create demo user: user1 / password
# ---------------------------------------------------------------------------
printf "\nCreating demo user 'user1' ...\n"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "user1",
    "email": "user1@example.com",
    "firstName": "User",
    "lastName": "One",
    "enabled": true,
    "emailVerified": true,
    "credentials": [{"type": "password", "value": "password", "temporary": false}]
  }' \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/users")

if [ "$STATUS" = "201" ]; then
  echo "User 'user1' created."
elif [ "$STATUS" = "409" ]; then
  echo "User 'user1' already exists — continuing."
else
  echo "ERROR: Unexpected status $STATUS when creating user."; exit 1
fi

# ---------------------------------------------------------------------------
# Store the client secret as a Kubernetes Secret in the byo-redis namespace.
# Create the namespace first in case this script is run standalone.
# ---------------------------------------------------------------------------
kubectl create namespace byo-redis --dry-run=client -o yaml | kubectl apply -f - > /dev/null
printf "\nStoring client secret as Kubernetes Secret 'oauth' in namespace 'byo-redis' ...\n"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: oauth
  namespace: byo-redis
type: extauth.solo.io/oauth
data:
  client-secret: $(echo -n "${CLIENT_SECRET}" | base64)
EOF

printf "\nKeycloak realm setup complete.\n"
printf "  Realm    : %s\n" "$REALM"
printf "  Client   : %s\n" "$CLIENT_ID"
printf "  User     : user1 / password\n"
printf "  Issuer   : %s/realms/%s/\n" "$KEYCLOAK_URL" "$REALM"
