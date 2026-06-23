#!/bin/sh

pushd ..

kubectl delete -f routes/httpbin-httproute.yaml --ignore-not-found
kubectl delete -f referencegrants/overlays-httpbin/httproute-overlays-service-rg.yaml --ignore-not-found
kubectl delete -f apis/httpbin/httpbin.yaml --ignore-not-found
kubectl delete -f gateways/gw.yaml --ignore-not-found
kubectl delete namespace overlays-httpbin --ignore-not-found
kubectl delete namespace overlays --ignore-not-found
kubectl delete -f gateways/enterprise-kgateway-overlays.yaml --ignore-not-found
kubectl delete -f gateways/ent-kgateway-overlays-params.yaml --ignore-not-found

popd
