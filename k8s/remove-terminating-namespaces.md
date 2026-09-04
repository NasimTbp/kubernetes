# Removing terminated namespaces
## Step 1:
```
kubectl get namespace <YOUR_NAMESPACE> -o json > <YOUR_NAMESPACE>.json
```
> remove kubernetes from finalizers array which is under spec in file
## Step 2:
```
kubectl replace --raw "/api/v1/namespaces/<YOUR_NAMESPACE>/finalize" -f ./<YOUR_NAMESPACE>.json
```
## Step 3:
```
kubectl get namespace
```
