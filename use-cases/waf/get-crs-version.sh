#!/bin/sh
# Extracts the OWASP CRS version embedded in the WAF ExtProc server binary.
# Uses docker to pull the image and inspect the binary with strings, since
# the container is distroless (no shell, no tar — kubectl cp/exec won't work).

NAMESPACE="kgateway-system"

IMAGE=$(kubectl get pods -n "${NAMESPACE}" \
  -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' \
  | grep waf-server | head -1)

if [ -z "$IMAGE" ]; then
  echo "No waf-server image found in ${NAMESPACE}"
  exit 1
fi

echo "Image: ${IMAGE}"
echo ""

# --platform linux/amd64 needed on Apple Silicon
# Pull progress goes to stderr; only the container ID is captured on stdout.
CONTAINER_ID=$(docker create --platform linux/amd64 "${IMAGE}")
if [ $? -ne 0 ]; then
  echo "docker create failed. If the registry requires authentication, run: docker login us-docker.pkg.dev"
  exit 1
fi

# Try Entrypoint first, then Cmd
BINARY=$(docker inspect "${CONTAINER_ID}" --format '{{index .Config.Entrypoint 0}}' 2>/dev/null)
if [ -z "$BINARY" ]; then
  BINARY=$(docker inspect "${CONTAINER_ID}" --format '{{index .Config.Cmd 0}}' 2>/dev/null)
fi

# Fall back to known paths for ko-built Solo.io binaries
if [ -z "$BINARY" ]; then
  for candidate in /ko-app/waf-server /waf-server /server /app/waf-server; do
    if docker cp "${CONTAINER_ID}:${candidate}" /dev/null 2>/dev/null; then
      BINARY="${candidate}"
      break
    fi
  done
fi

echo "Binary: ${BINARY}"

if [ -z "$BINARY" ]; then
  echo "Could not determine binary path. Full image config:"
  docker inspect "${CONTAINER_ID}" --format '{{json .Config}}'
  docker rm "${CONTAINER_ID}" > /dev/null
  exit 1
fi

TMPFILE=$(mktemp /tmp/waf-server-XXXXXX)
docker cp "${CONTAINER_ID}:${BINARY}" "${TMPFILE}"
docker rm "${CONTAINER_ID}" > /dev/null

echo ""
echo "=== OWASP CRS version ==="
strings "${TMPFILE}" | grep -oE "OWASP_CRS/[0-9]+\.[0-9]+\.[0-9]+" | sort -u

rm -f "${TMPFILE}"
