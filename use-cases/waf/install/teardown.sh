#!/bin/sh

pushd ..

kubectl delete -f policies/custom-rules-traffic-policy.yaml --ignore-not-found
kubectl delete -f policies/custom-rules-waf-policy.yaml --ignore-not-found
kubectl delete -f routes/custom-rules-httproute.yaml --ignore-not-found
kubectl delete -f configmaps/custom-rules-cm.yaml --ignore-not-found
kubectl delete -f policies/ip-filter-traffic-policy.yaml --ignore-not-found
kubectl delete -f policies/ip-filter-waf-policy.yaml --ignore-not-found
kubectl delete -f routes/ip-filter-httproute.yaml --ignore-not-found
kubectl delete -f policies/traffic-policy.yaml --ignore-not-found
kubectl delete -f policies/waf-policy.yaml --ignore-not-found
kubectl delete -f routes/httpbin-httproute.yaml --ignore-not-found
kubectl delete -f referencegrants/waf-httpbin/httproute-waf-service-rg.yaml --ignore-not-found
kubectl delete -f apis/httpbin/httpbin.yaml --ignore-not-found
kubectl delete -f gateways/listener-policy.yaml --ignore-not-found
kubectl delete -f gateways/gw.yaml --ignore-not-found
kubectl delete namespace waf-httpbin --ignore-not-found
kubectl delete namespace waf --ignore-not-found
kubectl delete -f gateways/enterprise-kgateway-waf.yaml --ignore-not-found
kubectl delete -f gateways/ent-kgateway-waf-params.yaml --ignore-not-found

popd
