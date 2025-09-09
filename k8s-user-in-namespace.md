
# Report on **User Namespaces** and Root Privilege Verification in Kubernetes Pods

## 🎯  Introduction

In Kubernetes, the **User Namespaces** feature ensures that the **root user inside a container is not the real root on the host**. This significantly improves cluster security, as compromising a container does not grant full root access to the host.

For this feature to work, the container runtime must support user namespaces. **Containerd version 2.0 and above** provides full support for this capability. For upgrading containerd in Kubernetes, the following reference can be used:
[Upgrade Containerd in Kubernetes](https://www.vijay-narayanan.com/posts/kubernetes/upgrade-containerd-kubernetes/)

```
1. "Draining node..."
kubectl drain $(hostname) --ignore-daemonsets --delete-emptydir-data

2. "Stopping containerd..."
sudo systemctl stop containerd

3. "Removing old containerd..."
sudo apt remove -y containerd

4. "Downloading containerd "
you can find containerd in : https://github.com/containerd/containerd/releases

4. "Extracting and installing containerd..."
tar -xvf containerd-2.1.4-linux-amd64.tar.gz
sudo cp bin/* /usr/bin/

5. "Setting up systemd service..."
sudo systemctl unmask containerd
sudo nano /etc/systemd/system/containerd.service
puth the folling setting in that file:

🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹
# Copyright The containerd Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target dbus.service

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/bin/containerd

Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5

# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity

# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target

🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹

6. "Reload syatem"

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now containerd

7. "Generating config and setting SystemdCgroup..."
sudo mkdir -p /etc/containerd
sudo bash -c "containerd config default > /etc/containerd/config.toml"
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

8. "Restarting containerd and kubelet..."
sudo systemctl restart containerd
sudo systemctl restart kubelet

9. "Updated. Current containerd version:"
containerd --version

```

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
