
# Report on **User Namespaces** and Root Privilege Verification in Kubernetes Pods

## 🎯  Introduction

In Kubernetes, the **User Namespaces** feature ensures that the **root user inside a container is not the real root on the host**. This significantly improves cluster security, as compromising a container does not grant full root access to the host.

For this feature to work, the container runtime must support user namespaces. **Containerd version 2.0 and above** provides full support for this capability. For upgrading containerd in Kubernetes, the following reference can be used:
[Upgrade Containerd in Kubernetes](https://github.com/NasimTbp/kubernetes/blob/main/containerd-update.md)


---

## 🎯  Verification Methodology

To validate whether a pod with `hostUsers: false` actually maps root privileges to the host or not, the following procedure was carried out:

1. Identify the container ID using `crictl ps`:

   ```bash
   crictl ps | grep <pod_name>
   ```

2. Extract the PID of the main process from the host using `crictl inspect`:

   ```bash
   crictl inspect <container_id> | grep -i pid
   ```

3. Inspect the UID and GID mapping of the process on the host:

   ```bash
   cat /proc/<pid>/status | egrep "Uid|Gid"
   ```

This method clearly reveals whether the container’s root user is mapped to the real root on the host or to a remapped user.


---

## 🎯 In-Container Verification

For further confirmation, the following commands were executed inside the container to verify UID/GID and capabilities:

```bash
cat /proc/self/status | egrep "Uid|Gid"
capsh --print
ls -l /proc/1/root
```

---

## 🎯 Conclusion

* **User Namespaces** enhance pod-level security by preventing containers from running as real root on the host.
* Containers running on **Containerd < 2.0** do not support this feature; root inside the container is mapped directly to root on the host.
* Containers running on **Containerd ≥ 2.0** run with remapped UIDs/GIDs, ensuring that the root inside the container is isolated from the host.
* Practical verification using `crictl` and `/proc/<pid>/status` confirmed that on Worker3, root privileges are restricted, while on Worker2 they are not.

---
