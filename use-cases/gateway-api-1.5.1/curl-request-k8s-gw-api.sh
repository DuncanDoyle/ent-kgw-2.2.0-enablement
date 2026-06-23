#!/bin/sh

GW_IP=${GW_IP:-$(kubectl get gateway gw -n gwapi151 -o jsonpath='{.status.addresses[0].value}')}

if [ -z "$GW_IP" ]; then
  echo "Could not determine GW_IP. Is the gateway deployed and does it have an address?"
  exit 1
fi

curl -v --resolve "api.example.com:80:${GW_IP}" http://api.example.com/get
