#!/bin/sh

set -eu

LOG_LEVEL="${LOG_LEVEL:-INFO}"

log_level_num() {
  case "$1" in
    DEBUG) echo 10 ;;
    INFO)  echo 20 ;;
    WARN)  echo 30 ;;
    ERROR) echo 40 ;;
    *)     echo 20 ;;
  esac
}

log() {
  LEVEL="$1"
  MESSAGE="$2"

  CURRENT_LEVEL_NUM=$(log_level_num "${LOG_LEVEL}")
  MESSAGE_LEVEL_NUM=$(log_level_num "${LEVEL}")

  if [ "${MESSAGE_LEVEL_NUM}" -ge "${CURRENT_LEVEL_NUM}" ]; then
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [${LEVEL}] ${MESSAGE}"
  fi
}

k8s_time() {
  date -u +"%Y-%m-%dT%H:%M:%S.000000Z"
}

LOCK_NAME="lke-acl-update-lock"
LOCK_NAMESPACE="lke-acl-operator"
LOCK_TTL_SECONDS=60
CONFIGMAP_NAMESPACE="lke-acl-operator"

NODE_NAME="${NODE_NAME}"
LKE_CLUSTER_ID="${LKE_CLUSTER_ID}"
LINODE_TOKEN="${LINODE_TOKEN}"

ACL_LABEL_KEY="${ACL_LABEL_KEY}"
ACL_TAINT_KEY="${ACL_TAINT_KEY}"

STATIC_ACL_CIDRS=$(echo "${STATIC_ACL_CIDRS}" | tr ',' '\n' | sed '/^$/d')

log "INFO" "Starting ACL agent on node: ${NODE_NAME}"

NODE_IP=$(kubectl get node "${NODE_NAME}" -o json \
  | jq -r '
    .status.addresses[]
    | select(.type=="ExternalIP")
    | .address
    | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"))
  ' | head -n1)

if [ -z "${NODE_IP}" ] || [ "${NODE_IP}" = "null" ]; then
  log "ERROR: Could not determine node ExternalIP"
  exit 1
fi

NODE_CIDR="${NODE_IP}/32"

log "INFO" "Detected node IPv4 CIDR: ${NODE_CIDR}"


acquire_lock() {
  log "INFO" "Node ${NODE_NAME} requesting ACL update lock"

  while true; do
    NOW_EPOCH=$(date +%s)

    if kubectl create configmap "${LOCK_NAME}" \
      -n "${LOCK_NAMESPACE}" \
      --from-literal=holder="${NODE_NAME}" \
      --from-literal=created_epoch="${NOW_EPOCH}" \
      >/dev/null 2>&1; then

      log "INFO" "Node ${NODE_NAME} acquired ACL update lock"
      return 0
    fi

    LOCK_JSON=$(kubectl get configmap "${LOCK_NAME}" \
      -n "${LOCK_NAMESPACE}" \
      -o json 2>/dev/null || true)

    HOLDER=$(echo "${LOCK_JSON}" | jq -r '.data.holder // "unknown"')
    CREATED_EPOCH=$(echo "${LOCK_JSON}" | jq -r '.data.created_epoch // "0"')

    AGE=$((NOW_EPOCH - CREATED_EPOCH))

    if [ "${AGE}" -gt "${LOCK_TTL_SECONDS}" ]; then
      log "INFO" "ACL update lock held by ${HOLDER} is stale (${AGE}s old). Deleting stale lock"

      kubectl delete configmap "${LOCK_NAME}" \
        -n "${LOCK_NAMESPACE}" \
        --ignore-not-found >/dev/null 2>&1 || true

      sleep 1
      continue
    fi

    log "INFO" "Node ${NODE_NAME} waiting for ACL update lock held by ${HOLDER}"

    sleep 5
  done
}

release_lock() {
  HOLDER=$(kubectl get configmap "${LOCK_NAME}" \
    -n "${LOCK_NAMESPACE}" \
    -o jsonpath='{.data.holder}' 2>/dev/null || true)

  if [ "${HOLDER}" = "${NODE_NAME}" ]; then
    log "INFO" "Node ${NODE_NAME} releasing ACL update lock"

    kubectl delete configmap "${LOCK_NAME}" \
      -n "${LOCK_NAMESPACE}" \
      --ignore-not-found >/dev/null 2>&1 || true

    log  "INFO" "Node ${NODE_NAME} released ACL update lock"
  else
    log "INFO" "Node ${NODE_NAME} did not release lock because current holder is ${HOLDER}"
  fi
}

acquire_lock
trap release_lock EXIT

# TEMP TEST ONLY: hold the lock to validate waiting behavior
#log "INFO" "Node ${NODE_NAME} holding ACL update lock for 60 seconds to test lock contention"
#sleep 60
#log "INFO" "Node ${NODE_NAME} completed temporary lock hold test"

CURRENT_ACL=$(curl -sS \
  -H "Authorization: Bearer ${LINODE_TOKEN}" \
  "https://api.linode.com/v4/lke/clusters/${LKE_CLUSTER_ID}/control_plane_acl")

CURRENT_IPV4=$(echo "${CURRENT_ACL}" \
  | jq -r '.acl.addresses.ipv4[]?')

MERGED_IPV4=$(printf "%s\n%s\n%s\n" \
  "${CURRENT_IPV4}" \
  "${STATIC_ACL_CIDRS}" \
  "${NODE_CIDR}" \
  | sed '/^$/d' \
  | sort -u)

IPV4_JSON=$(printf "%s\n" "${MERGED_IPV4}" \
  | jq -R . \
  | jq -s .)

PAYLOAD=$(jq -n \
  --argjson ipv4 "${IPV4_JSON}" \
  '{
    acl: {
      enabled: true,
      addresses: {
        ipv4: $ipv4,
        ipv6: []
      }
    }
  }')

log "INFO" "Updating LKE-E ACL"

curl -sS -X PUT \
  "https://api.linode.com/v4/lke/clusters/${LKE_CLUSTER_ID}/control_plane_acl" \
  -H "Authorization: Bearer ${LINODE_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}"

sleep 5

VERIFY=$(curl -sS \
  -H "Authorization: Bearer ${LINODE_TOKEN}" \
  "https://api.linode.com/v4/lke/clusters/${LKE_CLUSTER_ID}/control_plane_acl")

FOUND=$(echo "${VERIFY}" \
  | jq -r '.acl.addresses.ipv4[]?' \
  | grep -Fx "${NODE_CIDR}" || true)

if [ -z "${FOUND}" ]; then
  log "ERROR: Node IP not found in ACL after update"
  exit 1
fi

log "INFO" "ACL update verified successfully"

release_lock
trap - EXIT

log "INFO" "Adding node ready label"

if kubectl label node "${NODE_NAME}" "${ACL_LABEL_KEY}=true" --overwrite; then
  log "INFO" "Node ${NODE_NAME} labeled ${ACL_LABEL_KEY}=true"
else
  log "ERROR: Failed to label node ${NODE_NAME}"
  exit 1
fi

log "INFO" "Removing startup taint"

if kubectl taint nodes "${NODE_NAME}" \
  "${ACL_TAINT_KEY}=true:NoSchedule-" >/dev/null 2>&1; then
  log "INFO" "Removed startup taint from node ${NODE_NAME}"
else
  log "INFO" "Startup taint not present on node ${NODE_NAME}; nothing to remove"
fi

log "INFO" "ACL agent completed successfully"

sleep infinity
