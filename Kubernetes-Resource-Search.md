# 🎯 Report on Searching and Reviewing Kubernetes Resources and ArgoCD Applications

This report presents a set of practical commands for checking the existence of specific values across Kubernetes resources and reviewing configuration settings in ArgoCD Applications. The purpose of these commands is to quickly identify ConfigMaps, resources containing a specific IP address, and Applications with the `prune` option enabled in ArgoCD.

---

## 📌 1. Checking for a Specific Value in ConfigMaps

To verify whether a specific value such as `sms-app-hotfix-svc` exists among all ConfigMaps in the cluster, the following command can be used:

```bash
kubectl get configmap --all-namespaces -o yaml | grep "sms-app-hotfix-svc"
```

---

## 📌 2. Checking for a Specific Value Along with Namespace and ConfigMap Name

To find a specific value such as the IP address `172.x.x.x` along with its corresponding Namespace and ConfigMap name, use the following command:

```bash
kubectl get configmaps --all-namespaces -o json | jq -r '.items[] | select(.data | tostring | contains("172.x.x.x")) | "Namespace: \(.metadata.namespace)\nConfigMap: \(.metadata.name)\n---"'
```

### Explanation

This command retrieves all ConfigMaps in JSON format and uses `jq` to search within the `data` section for the target value.

### Output

* Namespace name
* ConfigMap name

### Use Case

Helpful when precise identification of where a specific IP address or value is being used is required.

---

## 📌 3. Searching Across All Kubernetes Resources

To search for a specific value such as the IP address `172.x.x.x` across all Kubernetes resources, use the following command:

```bash
kubectl get all --all-namespaces -o json | jq -r '.items[] | select(tostring | contains("172.x.x.x")) | "Namespace: \(.metadata.namespace)\nResource: \(.kind)\nName: \(.metadata.name)\n---"'
```

### Explanation

This command retrieves all major Kubernetes resources and searches the entire object structure for the target value.

### Output

* Namespace
* Resource type
* Resource name

### Use Case

Useful for performing a comprehensive check to determine where a specific value is being used.

---

## 📌 4. Checking for `prune: true` in ArgoCD Applications

To identify which Applications in ArgoCD have the `prune: true` setting enabled, use the following command:

```bash
kubectl get applications -n argocd -o json | jq -r '
.items[]
| select(.spec.syncPolicy.automated.prune == true)
| "Application: \(.metadata.name)\n---"'
```

### Explanation

This command reviews all Applications in the ArgoCD namespace and displays only those where automatic pruning of unused resources is enabled.

### Use Case

Useful for reviewing automated synchronization policies and preventing orphaned resources from remaining in the cluster.

---

## 📌 5. Counting the Number of Applications with `prune: true`

To calculate the total number of Applications with `prune: true`, use the following command:

```bash
kubectl get applications -n argocd -o json | jq ' [.items[] | select(.spec.syncPolicy.automated.prune == true) ] | length'
```

### Explanation

This command works similarly to the previous one, but instead of displaying Application names, it returns only the total count.

### Use Case

Useful for management reporting and obtaining an overall view of ArgoCD synchronization settings.

---

# Conclusion

The above commands provide an efficient way to review Kubernetes resources and ArgoCD configurations. Using `kubectl` together with `jq` allows accurate extraction and analysis of required information in a short time. This approach is especially valuable in large operational environments where the number of resources is high and manual inspection is inefficient.
