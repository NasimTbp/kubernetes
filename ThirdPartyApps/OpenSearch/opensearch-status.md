```bash
HOST="https://opensearch-logs-master.observability.svc.cluster.local:9200"
AUTH='admin:<password>'
```

## 1. Overall cluster health
```bash
curl -k -u "$AUTH" "$HOST/_cluster/health?pretty"
```
Key fields to watch: `status` (should be `green`), `unassigned_shards` (should be `0`).

## 2. Disk usage per node
```bash
curl -k -u "$AUTH" "$HOST/_cat/allocation?v"
```
Watch `disk.percent` — if it approaches 75%, the earlier problem could come back.

## 3. List of Jaeger indices with size and doc count
```bash
curl -k -u "$AUTH" "$HOST/_cat/indices/jaeger*?v&h=index,health,pri,rep,docs.count,store.size&s=index"
```

## 4. Check the ISM policy is actually attached and working
```bash
curl -k -u "$AUTH" "$HOST/_plugins/_ism/explain/jaeger-jaeger-span-2026-08-16?pretty"
```
Should show `policy_id: jaeger-retention-policy` and current state `hot`.

## 5. Job status (Kubernetes side)
```bash
kubectl get jobs -n observability
kubectl logs -n observability job/apply-jaeger-retention-policy
```

## 6. Live Jaeger logs (to confirm data is still being written)
```bash
kubectl logs -n observability deploy/jaeger --since=15m -f | grep -iE "error|fail"
```
