# 🎯 Adding New Worker Nodes to a Kubernetes Cluster with Kubespray

The purpose of this procedure is to add new worker nodes to an existing Kubernetes cluster in a standard, repeatable, and controlled way. In this approach, the new VMs are prepared first using the organization’s internal pre-install playbook. Then Kubespray facts are refreshed across the whole cluster, and finally only the new worker nodes are joined to the cluster using Kubespray’s scale playbook.


🟢 1. Run the Internal Pre-install Playbook on the New VMs

Before running the main Kubespray playbooks, the organization’s internal pre-install playbook must be executed on the new VMs. This playbook is located under:

```
extra_playbooks 
```

This step prepares the new VMs before they are joined to the Kubernetes cluster. It applies the required internal repository configuration, operating system settings, Kubernetes networking requirements, /etc/hosts entries, ip_forward, required packages, and other organization-specific prerequisites.

This playbook must be executed only on the new VMs, not on all existing cluster nodes.

Command:

```
ansible-playbook -i host.ini pre-install-joinNewNode.yml 
```

🚀 pre-install-joinNewNode.yml  file exists in the same directory

⚠️ Note: At this stage, the host.ini file should contain only the new VMs. Existing cluster nodes should not be included in this inventory, because the pre-install tasks are intended only for the new machines.

---

🟢 2. Prepare the Inventory

Before running the playbooks, the cluster inventory must be updated correctly. The inventory must follow the Kubespray inventory structure. A template already exists in the following path:

inventory/mycluster/inventory.ini 

The new worker nodes must be added to the correct groups in the inventory. The node names must also match the expected hostnames, because the same names will later be used in the --limit option and also when applying Kubernetes labels.

Inventory template:
```
[all:vars]
 ansible_become=true
 ansible_become_method=sudo
 ansible_port=4653
 ansible_become_password=------
 ansible_user=atadmin
 ansible_password=------

[all]
 dmz-k8s-mt1 ansible_host=dmz-k8s-mt1
 dmz-k8s-mt2 ansible_host=dmz-k8s-mt2
 dmz-k8s-mt3 ansible_host=dmz-k8s-mt3
 dmz-k8s-wt1 ansible_host=dmz-k8s-wt1
 dmz-k8s-wt2 ansible_host=dmz-k8s-wt2
 dmz-k8s-wt3 ansible_host=dmz-k8s-wt3
 dmz-k8s-wt4 ansible_host=dmz-k8s-wt4
 dmz-k8s-wt5 ansible_host=dmz-k8s-wt5
 dmz-k8s-wt6 ansible_host=dmz-k8s-wt6
 dmz-k8s-wt7 ansible_host=dmz-k8s-wt7

[kube_control_plane]
 dmz-k8s-mt1
 dmz-k8s-mt2
 dmz-k8s-mt3

[kube_node]
 dmz-k8s-wt1
 dmz-k8s-wt2
 dmz-k8s-wt3
 dmz-k8s-wt4
 dmz-k8s-wt5
 dmz-k8s-wt6
 dmz-k8s-wt7


[k8s_cluster:children]
kube_control_plane
kube_node
```

⚠️ Note: The important point is that the inventory must represent the full cluster state. It should not include only the new nodes. It must include all master nodes, existing worker nodes, and the new worker nodes. This is required for running facts.yml correctly.

---

🟢 3. Run facts.yml from the Main Kubespray Directory

After the new VMs are prepared, the Kubespray facts playbook must be executed. This command must be run from the main Kubespray directory, because Kubespray playbooks, roles, and inventory paths depend on the Kubespray directory structure.

First, go to the Kubespray directory:

```
cd /home/atadmin/Downloads/kubespray 
```

💻 Then run:

```
ansible-playbook -i inventory/mycluster/inventory.ini playbooks/facts.yml 
```

⚠️ Note: This playbook must be executed on all cluster nodes, not only on the new worker nodes. Kubespray needs updated facts from the whole cluster in order to correctly perform the scale operation. This includes the master nodes, existing workers, and the new worker nodes.

The inventory format mentioned in step 2 is especially important here, because Kubespray uses this inventory to understand the current cluster topology and how the new nodes should be added.

---
🟢 4. Run scale.yml Only on the New Worker Nodes

After facts.yml completes successfully, the Kubespray scale playbook must be executed to join the new worker nodes to the cluster. This command must also be run from the main Kubespray directory.

Example command:

ansible-playbook -i inventory/mycluster/inventory.ini playbooks/scale.yml --limit=dmz-k8s-wt6,dmz-k8s-wt7 

The --limit option is very important. It ensures that the scale operation is applied only to the new worker nodes. 

After this step completes successfully, the new nodes should be joined to the Kubernetes cluster. To verify the result, run the following command on one of the master nodes:

```
kubectl get nodes -o wide 
```
The new nodes should appear in the output and eventually reach the Ready state.

---
🟢 5. Apply Labels to the New Worker Nodes

After the new worker nodes have joined the cluster, the required Kubernetes labels must be applied manually. This step must be performed from a master node or any machine that has valid kubectl access to the cluster.

Example commands on the master node:

```
kubectl label nodes dmz-k8s-wt6 node-role.kubernetes.io/worker6=true kubectl label nodes dmz-k8s-wt7 node-role.kubernetes.io/worker7=true 
```
