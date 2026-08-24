# Initial Vault Setup After Deployment on Kubernetes

After deploying Vault on Kubernetes and confirming that the Vault pods are running, Vault is still not fully operational.

In this setup, Vault is configured in **HA mode** with three nodes and uses **Raft Integrated Storage**.

The main Vault pods are:

```text
vault-0
vault-1
vault-2
````

Vault Agent Injector is also running in the cluster.

---

## 🟢 1. Check Vault Pods

First, verify that all Vault pods have been created and are running:

```bash
kubectl get pods -n vault
```

A `Running` pod status only means that the Vault containers are running. It does not necessarily mean that Vault itself is ready to serve requests.

---

## 🟢 2. Initialize Vault

After a fresh Vault installation, the cluster must be initialized **only once**.

Initialization is performed on the first node, for example `vault-0`:

```bash
kubectl exec -it vault-0 -n vault -- vault operator init
```

During initialization, Vault generates the required information for sealing and unsealing the cluster.

In the current configuration, five Unseal Keys are generated:

```text
Unseal Key 1
Unseal Key 2
Unseal Key 3
Unseal Key 4
Unseal Key 5
```

An Initial Root Token is also generated.

The current configuration is:

```text
Total Shares = 5
Threshold    = 3
```

This means that five Unseal Key shares exist, but **any three different shares out of the five** are sufficient to unseal Vault.

> **Important:** Vault must be initialized only once. `vault-1` and `vault-2` must not be initialized separately.

---

## 🟢 3. Unseal vault-0

After initialization, Vault starts in the `Sealed` state.

The current status can be checked with:

```bash
kubectl exec -it vault-0 -n vault -- vault status
```

Initially, the expected status is similar to:

```text
Initialized    true
Sealed         true
Total Shares   5
Threshold      3
```

To start the unseal process, run:

```bash
kubectl exec -it vault-0 -n vault -- vault operator unseal
```

Vault will prompt for an Unseal Key.

Enter the first key.

Run the command again:

```bash
kubectl exec -it vault-0 -n vault -- vault operator unseal
```

Enter the second key.

Run the command for the third time:

```bash
kubectl exec -it vault-0 -n vault -- vault operator unseal
```

Enter the third key.

The unseal progress should change as follows:

```text
0/3
 ↓
1/3
 ↓
2/3
 ↓
Unsealed
```

After three valid shares are provided, the Vault status should become:

```text
Sealed    false
```

---

## 🟢 4. Join vault-1 to the Raft Cluster

After the first Vault node is initialized and unsealed, the second node must join the existing Raft cluster.

For `vault-1`, run:

```bash
kubectl exec -it vault-1 -n vault -- \
vault operator raft join http://vault-0.vault-internal:8200
```

A successful join should return something similar to:

```text
Joined    true
```

After joining the Raft cluster, `vault-1` must also be unsealed.

Run the following command three times:

```bash
kubectl exec -it vault-1 -n vault -- vault operator unseal
```

Each time, enter a different Unseal Key share.

Afterward, verify the status:

```bash
kubectl exec -it vault-1 -n vault -- vault status
```

The expected result is:

```text
Sealed    false
```

---

## 🟢 5. Join vault-2 to the Raft Cluster

The third node must also join the existing Raft cluster.

Run:

```bash
kubectl exec -it vault-2 -n vault -- \
vault operator raft join http://vault-0.vault-internal:8200
```

A successful operation should return:

```text
Joined    true
```

Then unseal `vault-2` using three different Unseal Key shares.

Run:

```bash
kubectl exec -it vault-2 -n vault -- vault operator unseal
```

three times, entering a valid Unseal Key share each time.

The process should look like:

```text
Share 1  →  Unseal Progress 1/3

Share 2  →  Unseal Progress 2/3

Share 3  →  Sealed false
```

---

## 🟢 6. Verify the Status of All Vault Nodes

After completing the previous steps, verify the status of all three Vault servers.

### vault-0

```bash
kubectl exec -it vault-0 -n vault -- vault status
```

### vault-1

```bash
kubectl exec -it vault-1 -n vault -- vault status
```

### vault-2

```bash
kubectl exec -it vault-2 -n vault -- vault status
```

For all three nodes, the expected status should include:

```text
Initialized    true
Sealed         false
Storage Type   raft
HA Enabled     true
```

---

## 🟢 7. Verify Raft Cluster Membership

Finally, verify the members of the Raft cluster:

```bash
kubectl exec -it vault-0 -n vault -- vault operator raft list-peers
```

In a three-node Vault cluster, all three nodes should be listed:

```text
vault-0
vault-1
vault-2
```

One node should act as the **Raft Leader**, while the other two nodes act as **Followers**.

---

## Process Summary

The overall Vault startup process after deployment is:

```text
Deploy Vault
     │
     ▼
Vault Pods Running
     │
     ▼
Initialize vault-0
     │
     ├── Generate 5 Unseal Keys
     └── Threshold = 3
     │
     ▼
Unseal vault-0
     │
     ├── Key 1
     ├── Key 2
     └── Key 3
     │
     ▼
vault-0 Unsealed
     │
     ├───────────────┐
     ▼               ▼
vault-1            vault-2
     │               │
 Raft Join        Raft Join
     │               │
 3 Keys           3 Keys
     │               │
 Unseal           Unseal
     │               │
     └───────┬───────┘
             ▼
       3-Node Raft
       Vault Cluster
             │
             ▼
       Vault Operational
```

---

## Next Steps

After this stage is completed, the Vault cluster itself is operational.

The next steps can include:

1. Configuring **Kubernetes Authentication**
2. Creating **Vault Policies**
3. Creating **Vault Roles**
4. Storing application secrets in Vault
5. Configuring **Vault Agent Injector**
6. Configuring applications to consume secrets from Vault
7. Configuring **Vault Backup and Raft Snapshots**
8. Testing Vault recovery and restore procedures

> **Security Note:** Unseal Keys and the Initial Root Token are highly sensitive credentials. They should never be stored in Git repositories, Kubernetes manifests, documentation repositories, or shared chat messages. Store them securely according to your organization's secret-management policy.

