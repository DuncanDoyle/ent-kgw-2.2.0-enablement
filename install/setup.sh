#!/bin/sh

pushd ..

# Label the gloo-system namespace. This label will be used later by the Gateway to determine from which namespaces its listeners will accept routes.
kubectl label namespaces kgateway-system --overwrite shared-gateway-access="true"

# Deploy the Gateway
#KGateway gateway deployment
kubectl create namespace ingress-gw --dry-run=client -o yaml | kubectl apply -f -
# kubectl apply -f gateways/ent-kgateway-parameters.yaml
kubectl apply -f gateways/gw.yaml

# Create namespaces if they do not yet exist
# kubectl create namespace ingress-gw --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace httpbin --dry-run=client -o yaml | kubectl apply -f -

# Label the default namespace, so the gateway will accept the HTTPRoute from that namespace.
printf "\nLabel default namespace ...\n"
kubectl label namespaces default --overwrite shared-gateway-access="true"

# Reference Grants
printf "\nDeploy Reference Grants ...\n"
kubectl apply -f referencegrants/httpbin-ns/httproute-default-service-rg.yaml
kubectl apply -f referencegrants/kgateway-system-ns/gw-ingress-gw-secret-rg.yaml

# Deploy the HTTPBin application
printf "\nDeploy HTTPBin application ...\n"
kubectl apply -f apis/httpbin/httpbin.yaml

# HTTPRoute
printf "\nDeploy HTTPRoute ...\n"
kubectl apply -f routes/api-example-com-httproute.yaml

popd