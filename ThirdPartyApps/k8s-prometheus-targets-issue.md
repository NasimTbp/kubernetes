The reason for the **connection refused** error is that some internal Kubernetes components such as `kube-scheduler` and `kube-controller-manager` listen by default only on the `127.0.0.1` address, 
meaning they are accessible only from the same node where they are running, and not from external pods or services like Prometheus. 
When Prometheus, running in a separate pod, tries to scrape these metrics, it sends requests from outside the node, so the connection is refused. 
To fix this, it is often suggested to change the `--bind-address` of these components from `127.0.0.1` to `0.0.0.0`, allowing them to be accessible on all network interfaces. 


# 🟢 controller-manager Connection refused:

##    💻 Change bind-address (default: 127.0.0.1):
```
sudo vi /etc/kubernetes/manifests/kube-controller-manager.yaml
```
```
apiVersion: v1
kind: Pod
metadata:
  ...
spec:
  containers:
  - command:
    - kube-controller-manager
    ...
    - --bind-address=<your control-plane IP or 0.0.0.0>
    ...
```
> Do it for all of your masters
> If you are using control-plane IP, you need to change livenessProbe and startupProbe host, too.
> no need to reset or reboot just refresh prometheus and all is well.




# 🟢 Kube-proxy Connection refused:

## 💻 Set the kube-proxy argument for metric-bind-address
```
kubectl edit cm/kube-proxy -n kube-system
```
```
...
kind: KubeProxyConfiguration
metricsBindAddress: 0.0.0.0:10249
...
```
```
kubectl delete pod -l k8s-app=kube-proxy -n kube-system
```
> every kube-proxy pod will be delete no further jobs to do.


# 🟢 kube-scheduler Connection refused:

##    💻 Change bind-address (default: 127.0.0.1):
```
sudo vi /etc/kubernetes/manifests/kube-scheduler.yaml
```
```
apiVersion: v1
kind: Pod
metadata:
  ...
spec:
  containers:
  - command:
    - kube-controller-manager
    ...
    - --bind-address=<your control-plane IP or 0.0.0.0>
    ...
```
# ETCD Connection refused:

##    💻 Change bind-address (default: 127.0.0.1):
```
sudo vi /etc/kubernetes/manifests/etcd.yaml
```
```
apiVersion: v1
kind: Pod
metadata:
  ...
spec:
  containers:
  - command:
    - kube-controller-manager
    ...
    - --listen-metrics-urls=http://0.0.0.0:2381
    ...
```
> Do it for all of your masters
> If you are using control-plane IP, you need to change livenessProbe and startupProbe host, too.
> no need to reset or reboot just refresh prometheus and all is well.
