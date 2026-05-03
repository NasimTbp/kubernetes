# Joining a New Worker Node to the Kubernetes Cluster

Ensure that the following are installed on the **new worker node**:

## 📌 Prerequisites

For installing Kubernetes prerequisites (like `kubeadm`, `kubelet`, and `kubectl`) on Ubuntu-based worker nodes, refer to this helpful guide:  
🔗 [Install Kubernetes on Ubuntu 22.04 - LinuxTechi](https://www.linuxtechi.com/install-kubernetes-on-ubuntu-22-04/)

---

Once the required tools are installed on the new node, you can join it to the Kubernetes cluster by following the steps below:

## 🚀 Step 1: Generate the Join Command (on Control Plane Node)

Run the following command **on the control plane (master) node** to generate a secure join command for worker nodes:

```
sudo kubeadm token create --print-join-command
```


## 🖥️ Step 2: Join the Worker Node to the Cluster
Run the generated kubeadm join command on the new worker node:

##  Example output

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

```
kubectl get nodes
```

You should see something like:

NAME            STATUS   ROLES           AGE    VERSION
hq-k8s-testm    Ready    control-plane   321d   v1.32.5
hq-k8s-wtest1   Ready    worker1         3d1h   v1.32.5
hq-k8s-wtest2   Ready    worker2         3d     v1.32.5

NAME | STATUS | ROLES | AGE | VERSION 
--- | --- | --- | --- |---
hq-k8s-testm | Ready | control-plane | 321d | v1.32.5 
hq-k8s-wtest1 | Ready | worker1 | 3d1h | v1.32.5 
hq-k8s-wtest2 | Ready | worker2 | 3d | v1.32.5 

---

# ✅ Node Initialization Checklist in Kubernetes
When a new node is being added to the Kubernetes cluster, two key conditions must be met:
1. Node must be in Ready state – this means the node has successfully joined the cluster and is communicating with the control plane (master).
2. Node must be schedulable – this means the node is able to accept and run pods.
To ensure the second condition is met, the following critical system pods must be verified and running correctly
This means that when a new node is being added to the Kubernetes cluster, several system pods must be running properly on the node to ensure successful integration and schedulability

## Required Pods (in order of importance)

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

# 🧯 Troubleshooting – Common Issues When Adding a New Node
When adding a new node to a Kubernetes cluster, you may encounter issues that prevent pods from running correctly or block network communication. Below are two common issues typically seen on new nodes and how to resolve them:

## ❌ Issue1: Pods Failing to Connect to NFS
Pods that use NFS volumes (e.g., for PersistentVolumes) may fail to mount 

Solution: Run the following commands on the new node to install NFS support:

```
sudo apt update
sudo apt install nfs-common
```



## ❌ Issue2: Network Communication Problems (kube-proxy & Pod Networking)

Pods cannot communicate with each other because kube-proxy fails to operate properly

Cause: The nf_conntrack kernel module, which handles network connection tracking, may not be loaded by default on some OS/kernel versions.

Solution: Manually load the module and ensure it's loaded on reboot:

```
sudo modprobe nf_conntrack
echo "nf_conntrack" | sudo tee /etc/modules-load.d/nf_conntrack.conf
```

💡 Note: These two issues are commonly encountered only on newly added nodes and should be addressed before joining the node to the cluster.

---

# ⚙️ Configuring containerd to Use systemd as the cgroup Driver
When setting up worker nodes in a Kubernetes cluster, it is essential to configure containerd to use systemd as the cgroup driver. 
A mismatch between the cgroup driver used by containerd and the one used by kubelet (typically systemd) can lead to resource management issues and unstable pod behavior. 
To ensure compatibility and avoid such problems, containerd’s default configuration must be updated.

## Steps to configure containerd:

1. Generate the default configuration file and save it to /etc/containerd/config.toml:

```
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
```

2. Modify the configuration file to enable systemd as the cgroup driver:

```
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
```

3. Restart and enable the containerd service to apply the changes:

```
sudo systemctl restart containerd
```

💡 After performing these steps, containerd will be properly aligned with kubelet in terms of cgroup management, ensuring more stable and predictable behavior of workloads on the worker nodes.
