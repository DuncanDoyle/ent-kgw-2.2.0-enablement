#!/bin/sh

pushd ..

kubectl delete -f policies/traffic-policy.yaml --ignore-not-found
kubectl delete -f policies/ratelimit-config.yaml --ignore-not-found
kubectl delete -f policies/authconfig.yaml --ignore-not-found
kubectl delete secret oauth -n byo-redis --ignore-not-found
kubectl delete -f routes/keycloak-httproute.yaml --ignore-not-found
kubectl delete -f routes/httpbin-httproute.yaml --ignore-not-found
kubectl delete -f referencegrants/keycloak/httproute-byo-redis-keycloak-rg.yaml --ignore-not-found
kubectl delete -f referencegrants/byo-redis-httpbin/httproute-byo-redis-service-rg.yaml --ignore-not-found
kubectl delete -f apis/httpbin/httpbin.yaml --ignore-not-found
kubectl delete -f redis/valkey-auth.yaml --ignore-not-found
kubectl delete -f redis/valkey-ratelimit.yaml --ignore-not-found
kubectl delete -f gateways/gw.yaml --ignore-not-found
kubectl delete namespace byo-redis-httpbin --ignore-not-found
kubectl delete namespace byo-redis --ignore-not-found
kubectl delete -f gateways/enterprise-kgateway-byo-redis.yaml --ignore-not-found
kubectl delete -f gateways/ent-kgateway-byo-redis-params.yaml --ignore-not-found

popd
