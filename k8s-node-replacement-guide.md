# Joining a New Worker Node to the Kubernetes Cluster

Once the required tools such as `kubeadm`and `kubelet` are installed on the new node, you can join it to the Kubernetes cluster by following the steps below:

## 📌 Prerequisites

Ensure that the following are installed on the **new worker node**:

- `kubeadm`
- `kubelet`

Also make sure:

- The node can reach the control plane over the network.
- The control plane node has port **6443** open for API communication.

---

## 🚀 Step 1: Generate the Join Command (on Control Plane Node)

Run the following command **on the control plane (master) node** to generate a secure join command for worker nodes:

```bash
sudo kubeadm token create --print-join-command
```bash

##  Example output

kubeadm join 172.11.11.2:6443 --token zvga31.e67apmsqzro3vgad --discovery-token-ca-cert-hash sha256:3c82536953bfc455c713133685196b82d17428ee2005b665909d5dbb29ac6619



## 🖥️ Step 2: Join the Worker Node to the Cluster
Run the generated kubeadm join command on the new worker node:

```bash
sudo kubeadm join 172.11.11.2:6443 --token zvga31.e67apmsqzro3vgad \
--discovery-token-ca-cert-hash sha256:3c82536953bfc455c713133685196b82d17428ee2005b665909d5dbb29ac6619
```bash

After running this command, the worker node should attempt to register with the cluster


## 🏷️ Step 3: Label the Node  
📍 _Run this on the **control plane node**_

```bash
kubectl label nodes hq-k8s-wtest1 node-role.kubernetes.io/worker=true
```bash

Replace hq-k8s-wtest1 with the actual node name (use kubectl get nodes to find it).

## ✅ Step 4: Verify Node Status
📍 Run this on the control plane node

```bash
kubectl get nodes
```bash

You should see something like:

NAME            STATUS   ROLES           AGE    VERSION
hq-k8s-testm    Ready    control-plane   321d   v1.32.5
hq-k8s-wtest1   Ready    worker1         3d1h   v1.32.5
hq-k8s-wtest2   Ready    worker2         3d     v1.32.5


-----------------------------------------------------------------

# Node Initialization Checklist in Kubernetes
When a new node is being added to the Kubernetes cluster, two key conditions must be met:
1. Node must be in Ready state – this means the node has successfully joined the cluster and is communicating with the control plane (master).
2. Node must be schedulable – this means the node is able to accept and run pods.
To ensure the second condition is met, the following critical system pods must be verified and running correctly
This means that when a new node is being added to the Kubernetes cluster, several system pods must be running properly on the node to ensure successful integration and schedulability

## ✅ Required Pods (in order of importance)

1. **kube-proxy**  
   - Namespace: `kube-system`  
   - Handles network routing rules on each node.

2. **coredns**  
   - Namespace: `kube-system`  
   - Provides DNS resolution for services and pods.

3. **calico-api-server**  
   - Namespace: `calico-apiserver`  
   - Exposes Calico configuration and status via Kubernetes API.

4. **calico-node**  
   - Namespace: `calico-system`  
   - Handles network policy enforcement and IP address management.

5. **calico-node-driver**  
   - Namespace: `calico-system`  
   - Custom driver for advanced networking (if enabled in the cluster).

---

## 🔧 Troubleshooting Strategy

If any errors occur during node initialization, the above pods should be verified and troubleshooted **in the specified order**.

For each pod:

- Check pod status:
  ```bash
  kubectl get pods -n <namespace>
