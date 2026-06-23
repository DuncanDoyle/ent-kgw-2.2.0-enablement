#!/bin/sh

pushd ..

kubectl delete -f routes/external-tcpbin-tlsroute.yaml --ignore-not-found
kubectl delete -f backends/tcpbin-com-backend.yaml --ignore-not-found
kubectl delete -f routes/mtls-httproute.yaml --ignore-not-found
kubectl delete -f routes/api-example-com-httproute.yaml --ignore-not-found
kubectl delete -f apis/httpbin/httpbin.yaml --ignore-not-found
kubectl delete -f referencegrants/gwapi151-httpbin/httproute-gwapi151-service-rg.yaml --ignore-not-found
kubectl delete -f listenersets/listenerset.yaml --ignore-not-found
kubectl delete -f gateways/gw.yaml --ignore-not-found
kubectl delete secret gateway-server-tls -n gwapi151 --ignore-not-found
kubectl delete configmap client-ca -n gwapi151 --ignore-not-found
kubectl delete namespace gwapi151-httpbin --ignore-not-found
kubectl delete namespace gwapi151 --ignore-not-found

popd
