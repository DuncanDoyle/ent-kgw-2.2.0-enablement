
#!/bin/sh

source ./env.sh

if [ -z "$ENT_KGW_LICENSE_KEY" ]
then
   echo "Solo Enterprise for Kgateway License Key not specified. Please configure the environment variable 'ENT_KGW_LICENSE_KEY' with your Solo Enterprise for Kgateway License Key."
   exit 1
fi

export ENT_KGW_CRDS_URL="oci://us-docker.pkg.dev/solo-public/enterprise-kgateway/charts/enterprise-kgateway-crds"
export ENT_KGW_URL="oci://us-docker.pkg.dev/solo-public/enterprise-kgateway/charts/enterprise-kgateway"

if [ "$DEV_VERSION" = true ] ; then

   printf "\nSolo Enteprise for Kgateway Dev versions not yet available!\n"
   exit 1

#   if [ -z "$MINIKUBE_PROFILE" ]
#   then
#      echo "Minikube profile not specified. When installing a DEV release of Solo Enterprise for kgateway, you need to specify the Minikube profile to which the images need to be pushed."
#      echo "Please configure the environment variable 'MINIKUBE_PROFILE' with the Minikube profile name you're using for this demo."
#      exit 1
#   fi

#   export ENT_KGW_CRDS_URL="oci://us-docker.pkg.dev/developers-369321/gloo-gateway/charts/gloo-gateway-crds"
#   export ENT_KGW_URL="oci://us-docker.pkg.dev/developers-369321/gloo-gateway/charts/gloo-gateway"

#   printf "\nPull GGv2 Controller image ...\n"
#   docker pull us-docker.pkg.dev/developers-369321/gloo-gateway/gloo-gateway-controller:$ENT_KGW_VERSION
#   printf "\nLoading GGv2 Controller image in Minikube ...\n"
#   minikube -p $MINIKUBE_PROFILE image load us-docker.pkg.dev/developers-369321/gloo-gateway/gloo-gateway-controller:$ENT_KGW_VERSION

#   printf "\nPull GGv2 Envoy Wrapper image ...\n"
#   docker pull us-docker.pkg.dev/developers-369321/gloo-gateway/envoy-wrapper:$GGV2_VERSION
#   printf "\nLoading GGv2 Envoy Wrapper image in Minikube...\n"
#   minikube -p $MINIKUBE_PROFILE image load us-docker.pkg.dev/developers-369321/gloo-gateway/envoy-wrapper:$GGV2_VERSION

fi

#----------------------------------------- Install Gloo Gateway with K8S Gateway API support -----------------------------------------

printf "\nApply K8S Gateway CRDs ....\n"
# kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/$K8S_GW_API_VERSION/standard-install.yaml
# Note: --server-side is a workaround. If not applied, the HTTPRoute CRD will not install.
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/$K8S_GW_API_VERSION/experimental-install.yaml

# helm upgrade --install gloo glooe/gloo-ee --namespace gloo-system --create-namespace --set-string license_key=$GLOO_GATEWAY_LICENSE_KEY -f $GLOO_GATEWAY_HELM_VALUES_FILE --version $GLOO_GATEWAY_VERSION

# Install default KgatewayParameters for enterprise-kgateway GatewayClass
printf "\nInstall Solo Enterprise for Kgateway CRDs ....\n"
helm upgrade --install enterprise-kgateway-crds $ENT_KGW_CRDS_URL \
    --version $ENT_KGW_VERSION \
    --namespace $ENT_KGW_SYSTEM_NAMESPACE \
    --create-namespace \
    --set installExtAuthCRDs=true \
    --set installRateLimitCRDs=true \
    --set installEnterpriseListenerSetCRD=true

# Wait for CRD to be available.
sleep 2
kubectl wait --for=condition=Established crd/enterprisekgatewayparameters.enterprisekgateway.solo.io

pushd ../
printf "\nInstall shared EnterpriseKgatewayParameters for enterprise-kgateway GatewayClass ....\n"
kubectl apply -f gateways/shared-ent-kgateway-parameters.yaml
popd



printf "\nInstall Solo Enterprise for Kgateway ...\n"
helm upgrade --install enterprise-kgateway $ENT_KGW_URL \
    --version $ENT_KGW_VERSION \
    --namespace $ENT_KGW_SYSTEM_NAMESPACE \
    --create-namespace \
    --set-string licensing.licenseKey=$ENT_KGW_LICENSE_KEY \
    -f $ENT_KGW_HELM_VALUES_FILE



#----------------------------------------- Install Keycloak -----------------------------------------

pushd ../

# Install Keycloak
printf "\nInstall Keycloak ...\n"
# Create Keycloak namespace if it does not yet exist
kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -
# Label the httpbin namespace, so the gateway will accept the HTTPRoute from that namespace.
printf "\nLabel keycloak namespace ...\n"
kubectl label namespaces keycloak --overwrite shared-gateway-access="true"

kubectl apply -f keycloak/keycloak-secrets.yaml
kubectl apply -f keycloak/keycloak-db-pv.yaml
kubectl apply -f keycloak/keycloak-postgres.yaml
printf "\nWait for Keycloak Postgres readiness ...\n"
kubectl -n keycloak rollout status deploy/postgres

kubectl apply -f keycloak/keycloak.yaml
printf "\nWait for Keycloak readiness ...\n"
kubectl -n keycloak rollout status deploy/keycloak

popd