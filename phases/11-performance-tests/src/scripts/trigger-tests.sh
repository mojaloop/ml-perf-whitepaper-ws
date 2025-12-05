#!/bin/bash

set -e

export HTTPS_PROXY=socks5://127.0.0.1:1080

KUBECONFIG=../kubeconfigs/kubeconfig-k6.yaml
NAMESPACE=k6-test
VALUES_FILE=../values/values.yaml
RELEASE_NAME=k6-test-mojaloop


echo "Cleaning up old release for"
helm uninstall "$RELEASE_NAME" --kubeconfig "$KUBECONFIG" --namespace "$NAMESPACE" || true

echo "Deploying K6 test..."

helm upgrade --install "$RELEASE_NAME" ../mojaloop-k6-operator \
  -f "$VALUES_FILE" \
  --kubeconfig "$KUBECONFIG" \
  --namespace "$NAMESPACE" \
  --create-namespace

echo "✅ K6 tests triggered successfully"
