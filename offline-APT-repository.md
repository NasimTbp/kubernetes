This document is a technical report detailing the preparation, configuration, and use of an offline APT repository for installing and upgrading the core Kubernetes components (including `kubeadm`, `kubectl`, and `kubelet`) in environments without direct internet access.

🔗 This report is based of: https://wiki.scanframe.com/Configuration/Linux/nexus-apt-hosted-repo

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

# 📑 Phase Two Report – Creating an APT Hosted Repository in Nexus for Kubernetes Packages

### 🔍 1. Introduction

In this phase, we will transfer the previously downloaded Kubernetes packages (kubeadm, kubelet, kubectl) from an internet-enabled node to Nexus Repository and create an APT Hosted Repository. 
This repository will serve as the offline APT repo for cluster nodes.

🟢 The process includes:
```  
  🔹 Generating GPG keys (public and private) on the Nexus server.
  🔹 Creating and configuring the APT Hosted Repository in Nexus.
  🔹 Uploading the downloaded Debian packages into the repository.
  🔹 Preparing the public key for client nodes.
```
### 🔍 2. Downloading Kubernetes Packages (on the internet-enabled node)

💻 First, on a node with internet access (and configured proxy), download the required packages.
    We use apt-get download so that .deb files are retrieved without installation:
```
sudo apt-get update apt-get download kubelet=1.31.12-1.1 kubectl=1.31.12-1.1 kubeadm=1.31.12-1.1 
```
💻 The .deb files will be saved in the current directory. These files should then be transferred to the Nexus Repository VM (e.g., using scp). 
    Alternatively, these downloads could also be performed directly on the Nexus host if it has internet access.

---

### 🔍 3. Generating GPG Keys on the Nexus Server

APT repositories require package signing. Therefore, we create a GPG key pair on the Nexus server.

🔹 3.1 Install GPG
```
sudo apt-get update && sudo apt-get install -y gpg 
```

🔹 3.2 Generate a new key
```
gpg --gen-key 
```
  💻 During this step, you will be prompted for name, email, and passphrase. Once complete, the key pair will be generated.

🔹 3.3 List existing keys
```
gpg --list-keys 
```
  💻 The newly created key will appear with a Key ID. This Key ID will be required in later steps.

🔹 3.4 Export keys

💻 Public key (for clients):
```
gpg --armor --output nexus-apt-repo.public.gpg.key --export <KEY_ID> 
```

💻 Private key (for Nexus):
```
gpg --armor --output nexus-apt-repo.private.gpg.key --export-secret-key <KEY_ID>
```

💻 Binary format exports (optional):
```
gpg --output nexus-apt-repo.public.gpg --export <KEY_ID> gpg --output nexus-apt-repo.private.gpg --export-secret-key <KEY_ID> 
```

⚠️ Note: The private key must be provided in the Nexus Repository configuration under Signing Key for the offline APT repository.

---

### 🔍 4. Creating the APT Hosted Repository in Nexus

🟢 Log in to the Nexus Web UI.
```  
  🔹 Go to Repositories → Create repository → APT (hosted).
  🔹 Enter a repository name (e.g., offline-apt).
  🔹 In APT Settings → Signing Key, paste the contents of the private key (nexus-apt-repo.private.gpg.key) generated earlier.
  🔹 Set the distribution (e.g., jammy) and configure the passphrase for key recovery.
  🔹 Adjust other settings (Blob store, Cleanup policies) according to organizational standar   ds.
  🔹 Save to finalize repository creation.
```
---

### 🔍 5. Granting Upload Permissions

🟢 The user responsible for uploading .deb packages must have at least the following roles:
```  
  🔹 nx-repository-view-*-*-edit
  🔹 nx-repository-view-*-*-read
```
🟢 This can be configured under Security → Roles / Users in Nexus.

---

### 🔍 6. Uploading Debian Packages to Nexus

🟢 The downloaded .deb files from Step 2 must be uploaded into the repository.

💻 Method 1: Web UI
```  
  🔹 Navigate to Browse → offline-apt.
  🔹 Select Upload.
  🔹 Choose the .deb files and upload.
```
💻 Method 2: REST API / curl 

```
curl -u <username>:<password> --upload-file kubelet_1.31.12-1.1.deb \ http://<nexus-host>:8081/repository/offline-apt/ 
```

---

### 🔍 7. Preparing the Public Key for Clients

💻 After Nexus is set up, the public key (nexus-apt-repo.public.gpg.key) must be distributed to all client nodes. 
    This ensures that the cluster nodes can verify and install the signed packages from the offline APT repository.

💻 Transfer the public key to each client VM, so they can import it and fetch the Debian packages from the Nexus repository.

---- 

# 📑 Phase Three Report – Configuring Clients to Use the Offline APT Repository

### 🔍 1. Introduction

💻 After creating the APT Hosted Repository on the Nexus server and uploading the Kubernetes packages (Phase Two), 
    cluster nodes must be configured to download kubeadm, kubectl, and kubelet packages offline from the internal repository (offline-apt).

This process includes three main steps:
```  
 🔹 Transferring the Nexus public key to the nodes and placing it in the appropriate directory.
 🔹 Adding the Nexus repository to the APT sources list.
 🔹 Updating APT and testing package downloads.
```

---

### 🔍 2. Transferring the Nexus Public Key to Nodes

💻The public key (created in Phase Two: `nexus-apt-repo.public.gpg`) must be copied to each cluster node and placed in the `trusted.gpg.d` directory.

🔹 2.1. Copy the key to the node

⚠️ Assuming the key is located in `~/Downloads` --> yoy should move this file to /etc/apt/trusted.gpg.d/
```
chmod 644 ~/Downloads/nexus-apt-repo.public.gpg
sudo mv ~/Downloads/nexus-apt-repo.public.gpg /etc/apt/trusted.gpg.d/
```

🔹 2.2. Verify the key installation

```
ls -l /etc/apt/trusted.gpg.d/
```
The output should include the file `nexus-apt-repo.public.gpg`.

---

### 🔍 3. Adding the Nexus Repository to APT
📂 The Nexus repository must be added to the APT sources list. You can either edit `/etc/apt/sources.list` or create a new file in `/etc/apt/sources.list.d/`.

*Example:
```
sudo nano /etc/apt/sources.list
```
Add the following line:
```
# this is a private repository for OFFLINE Kubernetes and Debian packages
deb https://repo.mycompany.com/repository/offline-apt/ jammy main
```

---

### 🔍 4. Updating APT and Fixing Architecture Issues

💻 Update the APT cache:
```
sudo apt update
```

⚠️ If an i386 architecture error appears (since the packages are only for amd64), remove the i386 architecture:
```
sudo dpkg --remove-architecture i386
sudo apt update
```

💻 After this step, the output should show no errors, and the offline-apt repository will be available in the sources list.

---

### 🔍 5. Testing Kubernetes Package Downloads

💻 To verify proper functionality, download one of the packages:

```
cd /tmp
apt download kubeadm=1.31.12-1.1
```

🚀 The package should be successfully downloaded from the internal repository.

Sample output:
```
    Get:1 https://repo.mycompany.com/repository/offline-apt jammy/main amd64 kubeadm amd64 1.31.12-1.1 [11.5 MB]
    Fetched 11.5 MB in 0s (67.3 MB/s)
```




