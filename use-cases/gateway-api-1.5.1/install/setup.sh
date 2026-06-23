#!/bin/sh

pushd ..

# Create the namespace
kubectl create namespace gwapi151 --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespaces gwapi151 --overwrite shared-gateway-access="true"

# Generate mTLS certificates and store them as a Secret + ConfigMap in gwapi151.
# Must run before the Gateway is applied because the Gateway references these resources.
printf "\nGenerate mTLS certificates ...\n"
sh install/generate-certs.sh

# Deploy the Gateway
kubectl apply -f gateways/gw.yaml
# Deploy ListenerSet
kubectl apply -f listenersets/listenerset.yaml

#-------------------------------- Deploy HTTPRoute for internal HTTPBin service -------------------------

# Label the default namespace, so the gateway will accept the HTTPRoute from that namespace.
printf "\nCreate gwapi151-httpbin namespace ...\n"
kubectl create namespace gwapi151-httpbin --dry-run=client -o yaml | kubectl apply -f -

# Reference Grants
printf "\nDeploy Reference Grants ...\n"
kubectl apply -f referencegrants/gwapi151-httpbin/httproute-gwapi151-service-rg.yaml

# Deploy the HTTPBin application
printf "\nDeploy HTTPBin application ...\n"
kubectl apply -f apis/httpbin/httpbin.yaml

# HTTPRoute
printf "\nDeploy HTTPRoute ...\n"
kubectl apply -f routes/api-example-com-httproute.yaml

# mTLS HTTPRoute (Gateway API 1.5.1 — client certificate validation)
printf "\nDeploy mTLS HTTPRoute ...\n"
kubectl apply -f routes/mtls-httproute.yaml


#---------------------------------- Deploy TLSRoute for external TCPBin service ------------------------- 

printf "\nDeploy tcpbin-com backend ...\n"
kubectl apply -f backends/tcpbin-com-backend.yaml

printf "\nDeploy TLSRoute for external TCPBin service ...\n"
kubectl apply -f routes/external-tcpbin-tlsroute.yaml

popd