This document is a technical report detailing the preparation, configuration, and use of an offline APT repository for installing and upgrading the core Kubernetes components (including `kubeadm`, `kubectl`, and `kubelet`) in environments without direct internet access.


🎯  Objectives of this report:**

* Record the exact procedures for the operations and maintenance team.
* Enable repeatable execution in the future without internet connectivity.
* Provide an internal reference for other technical team members.

🎯 This document is organized into three main sections:**

* Downloading packages from official sources and initial preparation.
* Setting up an APT Hosted repository in Nexus and uploading the packages.
* Configuring cluster nodes to use the offline repository.


-----
# 📑 Step One Report – Downloading Kubernetes Packages from the Internet

### 🔍 1. Introduction:

  💻 Since the Kubernetes cluster nodes do not have direct internet access, the required packages (`kubeadm`, `kubelet`, `kubectl` and their dependencies) must be downloaded on a server with internet access.
     This report describes the steps for configuring the proxy (system-wide, Bash, APT, and containerd) and adding the Kubernetes repository on this server.

---

### 🔍 2. Proxy Configuration:


🔹 2.1. Proxy Settings in the GUI

💻 To configure the operating system to use the proxy globally, the following path was used:
```
🧩 Settings → Network → Network Proxy
```

💻 In the *Manual section, the following information was entered:
```
*HTTP Proxy: 188.x.x.x
*Port: 5xxx
```
🔹 2.2. Proxy Settings in Bash

💻 To allow command-line tools (such as `curl` and `apt`) to access the internet, the following environment variables were defined:
```
export http_proxy="http://188.x.x.x:5xxx"
export https_proxy="http://188.x.x.x:5xxx"
export HTTP_PROXY="http://188.x.x.x:5xxx"
export HTTPS_PROXY="http://188.x.x.x:5xxx"
export no_proxy="172.x.x.x:xxxx"
export NO_PROXY="172.x.x.x:xxxx"
```


🔹 2.3. Unsetting the Proxy (if needed)

💻 In cases where the proxy needs to be disabled, the following commands were used:
```
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY
```

🔹 2.4. Proxy Configuration for APT

💻 To configure APT to use the proxy, the following file was created:

📂 File Path: `/etc/apt/apt.conf.d/proxy.conf`
    Content:
```
Acquire::http::Proxy "http://188.x.x.x:5xxx/";
Acquire::https::Proxy "http://188.x.x.x:5xxx/";
Acquire::http::No-Proxy "repo.mycompany.com";
Acquire::https::No-Proxy "repo.mycompany.com";
```

🔹 2.5. Proxy Configuration for containerd

💻 Unlike Bash and APT, the containerd service requires separate proxy settings.
    First, create the required directory:
```
sudo mkdir -p /etc/systemd/system/containerd.service.d
```
💻 Then create the file:
📂 File Path: 
```
/etc/systemd/system/containerd.service.d/http-proxy.conf
```
Content:
```
[Service]
Environment="HTTP_PROXY=http://188.121.99.16:5366"
Environment="HTTPS_PROXY=http://188.121.99.16:5366"
Environment="NO_PROXY=localhost,127.0.0.1,.local,.internal,172.29.28.0/24"
```

💻 Apply the changes:
```
systemctl daemon-reload
systemctl restart containerd
```

---

### 🔍 3. Adding the Kubernetes Repository

🔹 3.1. Importing the GPG Key
💻 First, create the keyrings directory if it does not exist:
```
sudo mkdir -p -m 755 /etc/apt/keyrings
```
💻 Then fetch and store the Kubernetes GPG key (replace the version with the desired one):

```
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

🔹 3.2. Adding the Kubernetes APT Source

📌 Again, make sure the version matches your requirement:
```
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' \
| sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list
```
---

### 🔍 4. Checking Available Versions
💻 To view the list of installable versions:
```
sudo apt update
sudo apt-cache madison kubeadm
```

---

