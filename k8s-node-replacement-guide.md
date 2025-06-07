# Joining a New Worker Node to the Kubernetes Cluster

Ensure that the following are installed on the **new worker node**:

## 📌 Prerequisites

📚 For installing Kubernetes prerequisites (like `kubeadm`, `kubelet`, and `kubectl`) on Ubuntu-based worker nodes, refer to this helpful guide:  
🔗 [Install Kubernetes on Ubuntu 22.04 - LinuxTechi](https://www.linuxtechi.com/install-kubernetes-on-ubuntu-22-04/)

---

Once the required tools are installed on the new node, you can join it to the Kubernetes cluster by following the steps below:

## 🚀 Step 1: Generate the Join Command (on Control Plane Node)

Run the following command **on the control plane (master) node** to generate a secure join command for worker nodes:

```
sudo kubeadm token create --print-join-command
```

##  Example output

kubeadm join 172.11.11.2:6443 --token zvga31.e67apmsqzro3vgad --discovery-token-ca-cert-hash sha256:3c82536953bfc455c713133685196b82d17428ee2005b665909d5dbb29ac6619



## 🖥️ Step 2: Join the Worker Node to the Cluster
Run the generated kubeadm join command on the new worker node:

```
sudo kubeadm join 172.11.11.2:6443 --token zvga31.e67apmsqzro3vgad \
--discovery-token-ca-cert-hash sha256:3c82536953bfc455c713133685196b82d17428ee2005b665909d5dbb29ac6619
```

After running this command, the worker node should attempt to register with the cluster


## 🏷️ Step 3: Label the Node  
📍 _Run this on the **control plane node**_

```
kubectl label nodes hq-k8s-wtest1 node-role.kubernetes.io/worker=true
```

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

🧯 Troubleshooting – Common Issues When Adding a New Node
When adding a new node to a Kubernetes cluster, you may encounter issues that prevent pods from running correctly or block network communication. Below are two common issues typically seen on new nodes and how to resolve them:

❌ Issue: Pods Failing to Connect to NFS
Pods that use NFS volumes (e.g., for PersistentVolumes) may fail to mount 

📌 Solution
Run the following commands on the new node to install NFS support:

bash
sudo apt update
sudo apt install nfs-common

----

❌ Issue: Network Communication Problems (kube-proxy & Pod Networking)

Pods cannot communicate with each other because kube-proxy fails to operate properly

📌 Cause
The nf_conntrack kernel module, which handles network connection tracking, may not be loaded by default on some OS/kernel versions.

📌 Solution
Manually load the module and ensure it's loaded on reboot:

```bash
sudo modprobe nf_conntrack
echo "nf_conntrack" | sudo tee /etc/modules-load.d/nf_conntrack.conf
```bash

💡 Note: These two issues are commonly encountered only on newly added nodes and should be addressed before joining the node to the cluster.


