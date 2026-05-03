#!/bin/bash

# you can define these variable dynamic
NAMESPACE="redis-sentinel-test"       
POD_NAME="test-sentinel-redis-node-0"  
CONTAINER="sentinel"
SENTINEL_HOST="test-sentinel-redis.redis-sentinel-test.svc.cluster.local"
SENTINEL_PORT=26379
REDIS_PASSWORD="---"
MASTER_NAME="mymaster"

OUTPUT=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -c "$CONTAINER" -- sh -c "redis-cli -h $SENTINEL_HOST -p $SENTINEL_PORT <<EOF
AUTH $REDIS_PASSWORD
SENTINEL get-master-addr-by-name $MASTER_NAME
EOF
")

MASTER_HOST=$(echo "$OUTPUT" | sed -n '2p')
MASTER_POD=$(echo "$MASTER_HOST" | cut -d '.' -f1)

if [[ -z "$MASTER_POD" ]]; then
  echo "❌ Failed to detect Redis master."
  exit 1
fi

echo "✅ Detected Redis master pod: $MASTER_POD"

LABEL=$(kubectl get pod "$MASTER_POD" -n "$NAMESPACE" -o jsonpath="{.metadata.labels.master}")

if [[ "$LABEL" == "true" ]]; then
  echo "ℹ️ Master pod already labeled. No change."
  exit 0
fi

echo "🔄 Change detected. Updating labels..."

kubectl label pod "$MASTER_POD" -n "$NAMESPACE" master=true --overwrite

for pod in $(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=redis -o jsonpath="{.items[*].metadata.name}"); do
  if [[ "$pod" != "$MASTER_POD" ]]; then
    echo "🧹 Removing label from $pod"
    kubectl label pod "$pod" -n "$NAMESPACE" master- --overwrite || true
  fi
done

echo "✅ Labels updated."
