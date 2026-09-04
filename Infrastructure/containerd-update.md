containerd is a lightweight and efficient **Container Runtime** responsible for managing the lifecycle of containers, including operations such as pulling images, managing storage and snapshots, creating and running containers, and handling namespaces and networking. 
It is directly used by Kubernetes through the **CRI** and plays a key role in running Pods. 
Keeping containerd up to date is important because newer versions fix bugs and security issues, add features like support for user namespaces, and improve compatibility with Kubernetes. 
Updating containerd can be done via the system's **Package Manager** or by downloading the binary directly from GitHub, and after stopping the service and replacing the files, restarting the service makes it ready for use.

For upgrading containerd in Kubernetes, the following reference can be used:
🔗 [Upgrade Containerd in Kubernetes](https://www.vijay-narayanan.com/posts/kubernetes/upgrade-containerd-kubernetes/)

📌 01. "Draining node..."
```
kubectl drain $(hostname) --ignore-daemonsets --delete-emptydir-data
```

📌 02. "Stopping containerd..."
```
sudo systemctl stop containerd
```

📌 03. "Removing old containerd..."
```
sudo apt remove -y containerd
```

📌 04. "Downloading containerd "
you can find containerd in : https://github.com/containerd/containerd/releases


📌 05. "Extracting and installing containerd..."
```
tar -xvf containerd-2.1.4-linux-amd64.tar.gz
sudo cp bin/* /usr/bin/
```


📌 06. "Setting up systemd service..."
```
sudo systemctl unmask containerd
sudo nano /etc/systemd/system/containerd.service
```
🖥️ puth the folling setting in that file:

```
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

```


📌 07. "Reload syatem"
```
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now containerd
```


📌 08. "Generating config and setting SystemdCgroup..."
```
sudo mkdir -p /etc/containerd
sudo bash -c "containerd config default > /etc/containerd/config.toml"
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```


📌 09. "Restarting containerd and kubelet..."
```
sudo systemctl restart containerd
sudo systemctl restart kubelet
```



📌 10. "Updated. Current containerd version:"
```
containerd --version
```

---

📑 # containerd Slice/ControlGroup

💻 This command:

```
systemctl show containerd -p Slice -p ControlGroup
```

prints the systemd Slice and the cgroup path for the `containerd` service. The output shows that `containerd` is running under `system.slice` and its cgroup is `/system.slice/containerd.service` (so it is not under `kube.slice`).

💻 This command:
```
systemctl show kube.slice -p MemoryMax -p MemoryHigh
```
prints the memory limit settings for `kube.slice`. `MemoryHigh=infinity` and `MemoryMax=infinity` mean there is **no soft or hard RAM limit** configured on `kube.slice` itself.
