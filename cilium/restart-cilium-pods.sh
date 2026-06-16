#!/bin/bash
for node in raspberrypi4-1 raspberrypi4-3 raspberrypi4-4 raspberrypi4-5; do
  pod=$(kubectl get pod -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=$node -o jsonpath='{.items[0].metadata.name}')
  echo "Deleting $pod on $node..."
  kubectl delete pod $pod -n kube-system
  kubectl wait pod -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=$node --for=condition=Ready --timeout=120s
  echo "Ready. Waiting 30s..."
  sleep 30
done
