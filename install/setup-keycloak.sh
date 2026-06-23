#!/bin/sh

pushd ..

printf "\nDeploy Keycloak HTTPRoute ...\n"
kubectl apply -f routes/keycloak-example-com-httproute.yaml

popd