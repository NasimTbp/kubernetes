# 🎯 Report on Installing and Upgrading a Kubernetes Cluster Using Kubespray

## Table of Contents

01. [Overview](#overview)
02. [Selecting the Appropriate Kubespray Version](#selecting-the-appropriate-kubespray-version)
03. [Comparing the Official Kubespray Release with the Internal Repository](#comparing-the-official-kubespray-release-with-the-internal-repository)
04. [Inventory Structure and Cluster-Specific Configuration](#inventory-structure-and-cluster-specific-configuration)
05. [Reviewing `group_vars` Configuration](#reviewing-group_vars-configuration)
06. [Preparing Container Images for an Offline or Semi-Offline Environment](#preparing-container-images-for-an-offline-or-semi-offline-environment)
07. [Nexus Repository Structure](#nexus-repository-structure)
08. [Running Pre-Installation Playbooks](#running-pre-installation-playbooks)
09. [Reviewing and Using the Cluster Inventory File](#reviewing-and-using-the-cluster-inventory-file)
10. [Installing the Kubernetes Cluster](#installing-the-kubernetes-cluster)
11. [Upgrading the Kubernetes Cluster](#upgrading-the-kubernetes-cluster)
12. [Internal Workaround Related to `kube.py`](#internal-workaround-related-to-kubepy)
13. [Summary](#summary)

---

## ✅ Overview

This report describes the process of preparing, installing, and upgrading a Kubernetes cluster using Kubespray. The purpose of this process is to ensure that Kubernetes installation or upgrade operations are performed in a controlled, repeatable, and organization-specific manner, while also respecting the network restrictions of the environment.

In the current infrastructure, the virtual machines on which the Kubernetes cluster is installed do not have direct internet access. Instead, required container images and dependencies are obtained through an internal Nexus Repository. Therefore, before running Kubespray playbooks, it is necessary to carefully verify the Kubespray version, the target Kubernetes version, the inventory configuration, repository settings, offline image configuration, and all required images.

Kubespray is used both for initial Kubernetes cluster installation and for upgrading existing clusters. Since the environment is not a standard internet-connected environment, the process requires additional preparation compared to a normal Kubespray installation. In particular, internal repository addresses, offline image availability, cluster-specific inventories, addon configuration, CNI configuration, MetalLB configuration, container runtime settings, and internal company modifications must all be reviewed before running the main playbook.

The main goal of this process is not only to execute a playbook successfully, but also to make the installation or upgrade predictable, auditable, and reusable for different clusters such as development and production environments.

---

## ✅ Selecting the Appropriate Kubespray Version

For installing or upgrading a Kubernetes cluster, the `first` step is to select the appropriate Kubespray version. Each Kubespray release supports a specific range of Kubernetes versions, so before starting the operation, it must be verified that the target Kubernetes version is supported by the selected Kubespray version.

This verification should be performed by checking the official Kubespray repository on GitHub and reviewing the relevant version variables and default configuration files. The official Kubespray repository contains the default variables that define which Kubernetes version is used by that Kubespray release and which versions are supported or expected.For example, if the goal is to install or upgrade Kubernetes to version `v1.35.4` using Kubespray version `2.31`, it must first be confirmed that this Kubernetes version is supported by the selected Kubespray release and that the related variables can be properly configured.

During upgrades, it is also important to consider Kubernetes version compatibility rules. Kubernetes upgrades are usually expected to be performed carefully and, in many cases, step by step between supported minor versions. Therefore, upgrading across several minor versions directly without checking compatibility can introduce unnecessary risk. Before choosing the final target version, the current Kubernetes version, the target Kubernetes version, and the Kubespray release compatibility must all be reviewed.

You can find the Github page for kubespraybelow:

```
https://github.com/kubernetes-sigs/kubespray
```
---

## ✅ Comparing the Official Kubespray Release with the Internal Repository

After selecting the proper Kubespray version, the `internal company versio`n of the Kubespray repository should be compared with the `official release`. 

⚠️ This step is necessary because the company repository may contain internal modifications that are not present in the official Kubespray release.

For this purpose, the previously used Kubespray version in the company, for example version `2.30`, should be downloaded from GitHub and compared with the corresponding version available in the company’s internal GitLab repository. The objective of this comparison is to identify all internal changes made by the company on top of the official Kubespray release.

🔍 These changes may include:
- [kube.py](#internal-workaround-related-to-kubepy)
- inventory settings, 
- repository addresses, 
- container runtime configuration, 
- CNI configuration, 
- additional playbooks, 
- offline configuration files, 
- MetalLB settings, 
- ingress-related settings, 
- custom scripts, 
- Calico configuration,
- and any internal workarounds. 

These differences are important because they may be required for Kubespray to work correctly in the company’s environment.

To simplify this step, the two branches or directories can be compared using tools such as IntelliJ IDEA. Comparing branches or directories in an IDE makes it easier to identify changed files, added files, removed files, and modified variables. All modified files should be reviewed carefully, and the required internal changes should then be transferred in a controlled manner to the newer Kubespray version.

📌 This step should not be skipped. If internal changes from the previous working version are not migrated correctly, the new Kubespray version may fail during execution or may install a cluster with incorrect configuration.

🧯 Also, check the `notice` directory, as it contains practical notes, encountered issues, and lessons learned from previous executions.

---

## ✅ Inventory Structure and Cluster-Specific Configuration

In Kubespray, the inventory structure starts from the default `inventory/sample` directory. For each Kubernetes cluster, a separate inventory directory is created based on this sample directory, and the directory name is chosen according to the cluster name.

For example, in the path below, multiple cluster inventories can exist next to the default sample directory:

```text
E:\kubespray\inventory
```

An example directory structure can be as follows:

```text
Directory: E:\kubespray\inventory

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
d-----          6/9/2026  12:44 PM                local
d-----          6/9/2026  12:44 PM                mycluster-dev
d-----          6/9/2026  12:44 PM                mycluster-prod
d-----          6/9/2026  12:44 PM                sample
```

Each of these directories contains the inventory file and the specific configuration of the corresponding cluster. For example, `mycluster-dev` contains the configuration of the development cluster, while `mycluster-prod` contains the configuration of the production cluster.This separation makes it possible to manage different environments independently. It also prevents configuration changes in one environment from affecting another environment. For example, development and production clusters may have different IP ranges, different MetalLB pools, different ingress IPs, different node lists, and different addon settings. Keeping them in separate inventory directories makes these differences explicit and easier to maintain.

When preparing a new Kubespray version, the relevant cluster inventory directory should be created or migrated based on the existing working inventory from the previous version. The format and structure of the inventory should remain consistent with the previous successful deployments unless there is a clear reason to change it.

---

## ✅ Reviewing `group_vars` Configuration

The main configuration of each cluster is usually located under the `group_vars` directory of that cluster inventory. For example, for the development cluster, the path can be:

```text
E:\kubespray\inventory\mycluster-dev\group_vars
```

An example structure is shown below:

```text
Directory: E:\kubespray\inventory\mycluster-dev\group_vars

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
d-----          6/9/2026  12:44 PM                all
d-----          6/9/2026  12:44 PM                k8s_cluster
```

The two important directories in this path are usually `all` and `k8s_cluster`. When migrating configuration from the previous Kubespray version to the new version, all files inside these directories must be reviewed carefully. The review should not be limited to only a few known files, because important configuration may be distributed across several files.

The addon configuration is also very important. One of the important configuration files in this area is the addons file. This file may define whether components such as ingress controller, dashboard, metrics, cert-manager, MetalLB, or other additional services are enabled or disabled. If this file is transferred incorrectly or if its changes are ignored, required cluster services may not be enabled after installation or upgrade, or they may run with incorrect settings.

Offline repository configuration must also be reviewed carefully. Since the nodes do not have direct internet access, image repositories and download URLs must point to the internal Nexus repository or other approved internal sources. If even one component still points to an external repository, the playbook may fail when it reaches that component.

In general, all files under `group_vars/all` and `group_vars/k8s_cluster` should be compared with the previous working version and updated carefully in the new Kubespray version.

---

## ✅ Preparing Container Images for an Offline or Semi-Offline Environment

In the current environment, the cluster virtual machines do not have internet access and obtain Kubernetes-related images through Nexus Repository. Because of this restriction, the required container images should be prepared before running the main Kubespray playbook.

Preparing images in advance has two major benefits. First, it increases the speed of playbook execution because the required images are already available in the internal repository. Second, it reduces the risk of playbook failure due to missing images. During installation or upgrade, Kubespray may need to pull many images, and the absence of even one required image can stop the process.

To extract the list of required images, the download configuration file of the selected Kubespray version should be reviewed. This file is usually located in a path similar to the following:

```text
kubespray/roles/kubespray_defaults/defaults/main/download.yml
```

This file defines the images required by Kubernetes components, CNI, DNS, container runtime, and other cluster components. After extracting the image list, the required `docker pull` commands, or equivalent commands for the container runtime in use, can be prepared and executed on the upstream and downstream repositories before running the playbook.

🚀 If needed, the content of the download file can be given to an assistant tool to generate a complete list of pull commands based on the image list and the internal registry addresses. However, the final output must always be reviewed by the responsible engineer to ensure that image names, tags, and registry paths exactly match the Kubespray configuration and the internal Nexus repository structure.

---

## ✅ Nexus Repository Structure

The repository structure in the current environment is designed around upstream and downstream Nexus repositories. The cluster nodes connect to an internal downstream Nexus. This downstream Nexus does not directly access the internet. Instead, it receives images from another upstream Nexus.

The general structure can be described as follows:

```text
Cluster Nodes  --->  Downstream Nexus  --->  Upstream Nexus
```

In this structure, all images required by the Kubernetes cluster must eventually be available from the downstream Nexus because the cluster nodes pull images from that repository.

An example image pull command for the downstream repository can be as follows:

```bash
docker pull repo.mycpmpany.com:8XXX/kube-controller-manager:v1.35.4
```

For the upstream repository, depending on the Nexus and registry addressing structure, the commands may look like the following:

```bash
docker pull localhost:80YZ/kube-controller-manager:v1.35.4
docker pull upstream-repo.mycpmpany.com:8XXX/kube-controller-manager:v1.35.4
```

⚠️ At this stage, it is important to ensure that the exact image names and repository paths match the offline settings used by Kubespray. If Kubespray uses a specific prefix or repository path for images, the same structure must exist inside Nexus.It is also recommended to test the cluster nodes’ access to the internal repository after pulling the images. This can be done by trying to pull a required image from one of the cluster nodes. If the node cannot pull the image manually, the Kubespray playbook will likely fail at the image pull stage.

---

## ✅ Running Pre-Installation Playbooks

In addition to preparing the required images, some environments require a set of operating system configurations to be applied to the nodes before installation or upgrade. These configurations may include enabling IP forwarding, configuring kernel modules, applying sysctl settings, preparing internal repositories, configuring DNS, configuring proxy settings, or applying other infrastructure prerequisites.

These pre-installation playbooks may apply changes that Kubespray expects to be already present on the nodes. For example, if IP forwarding or certain kernel parameters are not configured correctly, Kubernetes networking may not work properly after installation. Therefore, these playbooks should be treated as part of the full installation or upgrade procedure, not as optional scripts.

💻 In the current structure, additional playbooks for this purpose are located under the following path:

```text
E:\kubespray\extra_playbooks
```

An example structure is shown below:

```text
Directory: E:\kubespray\extra_playbooks

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
d-----          6/9/2026  12:44 PM                files
d-----          6/9/2026  12:44 PM                pre-post-install-dev
d-----          6/9/2026  12:44 PM                pre-post-install-prod
-a----          6/9/2026  12:44 PM             12 inventory
-a----          6/9/2026  12:44 PM           1090 migrate_openstack_provider.yml
-a----          6/9/2026  12:44 PM              8 roles
-a----          6/9/2026  12:44 PM           2414 upgrade-only-k8s.yml
-a----          6/9/2026  12:44 PM            152 wait-for-cloud-init.yml
```

For example, directories such as `pre-post-install-dev` and `pre-post-install-prod` may contain pre-installation and post-installation playbooks for development and production environments. Running these playbooks before the main Kubespray playbook helps ensure that the nodes are properly prepared for Kubernetes installation or upgrade.

Before running the main Kubespray playbook, the correct pre-installation playbook should be selected based on the target cluster. For example, the development cluster should use the playbooks prepared for the development environment, and the production cluster should use the playbooks prepared for the production environment.

---

## ✅ Reviewing and Using the Cluster Inventory File

The inventory file of each cluster is also a critical part of the process. It is usually located in a path such as:

```text
E:\kubespray\inventory\mycluster-dev\inventory.ini
```

An example structure of a cluster inventory directory is shown below:

```text
Directory: E:\kubespray\inventory\mycluster-dev

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
d-----          6/9/2026  12:44 PM                group_vars
-a----          6/9/2026  12:44 PM            741 inventory.ini
```

This file must be carefully reviewed and transferred from the previous working version to the new version, because the node grouping, role assignment, and host naming format are essential for correct Kubespray execution.

For security reasons, SSH passwords or sudo passwords should not be stored inside the inventory file. This is an important security practice because inventory files are usually stored in a repository and may be accessed by multiple people. Storing passwords directly in these files increases the risk of credential leakage.

Because passwords are not stored in the inventory, Ansible should be configured to request the required passwords at runtime when needed. This is done by using options such as `-k` and `--ask-become-pass`.

---

## ✅ Installing the Kubernetes Cluster

For initial cluster installation, the main Kubespray playbook is usually `cluster.yml`. This playbook performs the full installation of Kubernetes components and configures the cluster based on the inventory and group variables.

Since passwords are not stored in the inventory file, the installation command should include options for requesting the SSH password and the sudo password at runtime.

A sample installation command is shown below:

```bash
ansible-playbook cluster.yml \
  -i inventory/mycluster-prod/inventory.ini \
  -k --ask-become-pass
```

The `-k` option makes Ansible ask for the SSH password during execution. The `--ask-become-pass` option makes Ansible ask for the password required for privilege escalation, such as sudo.

The short form `-K` can also be used instead of `--ask-become-pass` if preferred:

```bash
ansible-playbook cluster.yml \
  -i inventory/mycluster-prod/inventory.ini \
  -k -K
```

If the playbook needs to run commands with root privileges, it must be verified that Ansible become settings and the permissions of the selected user are correctly configured on all nodes.

Before running the installation playbook, the following items should be verified: 
- the selected Kubespray version must support the target Kubernetes version, 
- the inventory must correctly define all nodes and roles, 
- all required group variables must be migrated, 
- offline repository addresses must be correct, 
- required images must be available in Nexus, 
- and pre-installation playbooks must have been executed successfully.

---

## ✅ Upgrading the Kubernetes Cluster

For upgrading an existing Kubernetes cluster with Kubespray, the `upgrade-cluster.yml` playbook should be used instead of `cluster.yml`. This playbook upgrades the Kubernetes cluster according to the target version and the configuration defined in Kubespray.

In this case, the target Kubernetes version must be specified using the `kube_version` variable. If the internal structure requires defining the minimum allowed Kubernetes version for upgrade, the `kube_version_min_required` variable can also be provided.

Since passwords are not stored in the inventory file, the upgrade command should also include the options for requesting SSH and sudo passwords at runtime.

A sample upgrade command is shown below:

```bash
ansible-playbook upgrade-cluster.yml \
  -i inventory/mycluster-prod/inventory.ini \
  -e kube_version=v1.35.4 \
  -e kube_version_min_required=v1.27.0 \
  -k --ask-become-pass
```

The same command can also be written with the short sudo password option:

```bash
ansible-playbook upgrade-cluster.yml \
  -i inventory/mycluster-prod/inventory.ini \
  -e kube_version=v1.35.4 \
  -e kube_version_min_required=v1.27.0 \
  -k -K
```

The `kube_version` variable defines the Kubernetes version that Kubespray should install during the upgrade. The `kube_version_min_required` variable can be used when the playbook or internal process needs to ensure that the current cluster version is not older than a specific minimum version.It is important to ensure that the version upgrade path is supported. The current Kubernetes version, the target Kubernetes version, and the Kubespray release must all be compatible. If the upgrade path is too large, it may be necessary to perform multiple intermediate upgrades instead of one direct upgrade.

---

## 📍📍📍 Internal Workaround Related to `kube.py`

During one execution, an issue was observed in the `kube.py` file. In that case, `kube.py` referred to a path where another Python script was expected to be executed, but during playbook execution, Kubespray could not read or resolve the path properly, and the target script was not executed.

After investigation, it was decided to place the content of that Python script directly inside the `kube.py` file, instead of referring to an external path. This allowed the required logic to be executed directly and avoided the path resolution issue.

This change should be documented as an internal workaround and reviewed again during future upgrades, because newer Kubespray versions may change the related file structure or provide a more standard solution.

It is also recommended to keep such local changes in a clearly defined internal branch so they remain traceable during future migrations. If the internal repository contains this workaround, then during migration to a newer Kubespray version, the modified file should be compared carefully with both the old internal version and the new official Kubespray version.

This type of workaround should not be copied blindly. It should first be checked whether the same issue still exists in the new Kubespray version. If the issue has been resolved upstream or if the file structure has changed, the workaround may need to be removed or rewritten.

---

## 🚀 Summary

Installing or upgrading Kubernetes using Kubespray in an offline or semi-offline environment is not limited to simply running a playbook. It requires careful preparation of versions, repositories, images, inventories, and cluster-specific configuration files.The most important part of the work is comparing the official Kubespray release with the company’s internal version and transferring the necessary internal changes to the new version in a controlled way. Without this step, important company-specific settings or workarounds may be lost.

After that, the required images should be extracted from the Kubespray download configuration and prepared in both upstream and downstream Nexus repositories. This preparation improves execution speed and reduces the risk of image pull failures during installation or upgrade.

Then, inventory settings, group variables, addons, MetalLB, Calico, containerd, offline repositories, and IP ranges must be reviewed and applied carefully. These settings define the actual behavior of the cluster and must match the target environment.

The pre-installation playbooks should also be executed before the main Kubespray playbook, because they may apply required operating system and infrastructure settings on the nodes.

For installation, the `cluster.yml` playbook is used. For upgrade, the `upgrade-cluster.yml` playbook is used. Because passwords are not stored in the inventory file for security reasons, the commands should include runtime password prompts such as `-k` and `--ask-become-pass`.

Following these steps reduces the risk of failure, improves execution speed, and makes the installation or upgrade process more repeatable. Documenting all internal changes, especially changes such as modifications to `kube.py` or changes to Kubespray default files, is essential for future upgrades. The more clearly these changes are documented and structured, the easier and safer it will be to maintain the clusters across future Kubespray versions.
