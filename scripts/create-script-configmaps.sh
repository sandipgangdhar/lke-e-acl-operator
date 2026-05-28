#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="lke-acl-operator"

kubectl create configmap acl-agent-script \
  --from-file=scripts/acl-agent.sh \
  -n "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -
