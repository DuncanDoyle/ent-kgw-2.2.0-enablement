#!/bin/sh

pushd ..

kubectl delete -f policies/holepunch-traffic-policy.yaml --ignore-not-found
kubectl delete -f policies/denylist-traffic-policy.yaml --ignore-not-found
kubectl delete -f policies/allowlist-traffic-policy.yaml --ignore-not-found
kubectl delete -f routes/httpbin-holepunch-httproute.yaml --ignore-not-found
kubectl delete -f routes/httpbin-denylist-httproute.yaml --ignore-not-found
kubectl delete -f routes/httpbin-allowlist-httproute.yaml --ignore-not-found
kubectl delete -f routes/httpbin-default-httproute.yaml --ignore-not-found
kubectl delete -f referencegrants/acl-httpbin/httproute-acl-service-rg.yaml --ignore-not-found
kubectl delete -f gateways/listener-policy.yaml --ignore-not-found
kubectl delete -f gateways/gw.yaml --ignore-not-found
kubectl delete namespace acl-httpbin --ignore-not-found
kubectl delete namespace acl --ignore-not-found
kubectl delete -f gateways/enterprise-kgateway-acl.yaml --ignore-not-found
kubectl delete -f gateways/ent-kgateway-acl-params.yaml --ignore-not-found

popd
