#!/bin/bash

export ENT_KGW_VERSION="2.2.3"
export ENT_KGW_HELM_VALUES_FILE="ent-kgw-helm-values.yaml"
export K8S_GW_API_VERSION="v1.5.1"

# Controls whether we install from the standard product helm charts or from the dev charts.
export DEV_VERSION=false

export ENT_KGW_SYSTEM_NAMESPACE="kgateway-system"

# CLUSTER_NAME="gg-demo-single"
# GLOO_PLATFORM_VERSION="2.10.2"
# GLOO_PLATFORM_HELM_VALUES_FILE="gloo-platform-helm-values.yaml"

export KEYCLOAK_HOST=keycloak.example.com
export KC_ADMIN_PASS=admin