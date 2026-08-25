# 🎯 Manual Vault Recovery from Backup 

(Human-Driven Process, Without Automation)

## 🟢 Objective

This document describes the manual process that a human operator must follow to recover Vault in the event of a complete Vault failure, including the loss of both the Vault instance and the physical data stored on NFS.

The objective is to deploy a fresh Vault instance and restore the previous data, including secrets, policies, authentication methods, and other Vault configuration, from a snapshot file.

This process is **intentionally not implemented as an automated script**. The decision to initiate a Disaster Recovery process must always be made by a human after verifying the actual situation, rather than automatically based on a system's diagnosis.

If a script independently determines that "a disaster has occurred" and automatically starts deleting or replacing data, an incorrect diagnosis—for example, a temporary network outage—could result in the loss of live and healthy data.

## 🟢 Prerequisites

- A valid and recent snapshot file from the previous Vault instance, created using `vault operator raft snapshot save`.
- The small Vault instance dedicated to Auto-Unseal (`vault-unseal`) must be healthy, accessible, and unsealed. Without it, the new Vault instance cannot automatically unseal. See **Report 2** for more information.
- `kubectl` access to the Kubernetes cluster.
- SSH access to the main NFS server.

## 🟢 Procedure

### ① Step 1: Take a Fresh Snapshot of the Current Vault (If It Is Still Available)

```bash
kubectl exec -it vault-0 -n vault -- vault operator raft snapshot save /tmp/backup.snap
```

Copy the snapshot file out of the pod and store it somewhere outside the cluster:

```bash
kubectl cp vault/vault-0:/tmp/backup.snap ./vault-snapshot-final.snap
```

### ② Step 2: Verify That the Small Vault (KMS) Is Healthy

```bash
kubectl exec -it vault-unseal-0 -n vault-unseal -- vault status
```

You should see:

```text
Sealed: false
```

If it is not healthy, resolve this issue first. Without the KMS Vault, continuing with this recovery process is useless.

### ③ Step 3: Delete the Vault-Related Argo Application

Delete the corresponding Argo Application:

```bash
kubectl delete Application X
```

### ④ Step 4: Delete the Physical Data from NFS

SSH into the main NFS server and empty the Vault data directories:

```bash
ssh <user>@172.29.29.5

rm -rf /mnt/nfs-data/vault/data-vault/pv0/*
rm -rf /mnt/nfs-data/vault/data-vault/pv1/*
rm -rf /mnt/nfs-data/vault/data-vault/pv2/*
rm -rf /mnt/nfs-data/vault/audit-vault/pv0/*
rm -rf /mnt/nfs-data/vault/audit-vault/pv1/*
rm -rf /mnt/nfs-data/vault/audit-vault/pv2/*
```

> **Important:** This step is required because the PVCs use `reclaimPolicy: Retain`. Without deleting the physical data, the new Vault instance will connect to the old data and treat the situation as a simple restart rather than a real disaster recovery.

### ⑤ Step 5: Re-Apply the Argo Application to the Cluster

```bash
kubectl apply -f Application-X.yaml
```

Wait a few seconds for Argo to deploy Vault again:

```bash
kubectl get pods -n vault
```

### ⑥ Step 6: Verify That the New Vault Is Empty

```bash
kubectl exec -it vault-0 -n vault -- vault status
```

You should see:

```text
Initialized: false
```

This confirms that the storage is actually empty.

### ⑦ Step 7: Initialize the New Vault

Because Auto-Unseal is enabled, there is no longer a need for five Shamir keys. Instead, **Recovery Keys** are generated, and Vault will automatically become unsealed immediately after initialization:

```bash
kubectl exec -it vault-0 -n vault -- vault operator init -recovery-shares=5 -recovery-threshold=3
```

Store the output, including the **five Recovery Keys** and the **Initial Root Token**, in a secure location.

These credentials are only required for future emergency operations and are not required for daily unseal operations.

Verify that Vault has automatically unsealed:

```bash
kubectl exec -it vault-0 -n vault -- vault status
```

You should see:

```text
Sealed: false
```

without providing any key.

> ⚠️ **If `vault-unseal` is not being used**, follow the unseal procedure described in the **Initial Setup** report.

### ⑧ Step 8: Copy the Snapshot File into the Pod

```bash
kubectl cp ./vault-snapshot-final.snap vault/vault-0:/tmp/restore.snap
```

### ⑨ Step 9: Log in Using the New Root Token and Restore the Snapshot

Enter the Vault pod:

```bash
kubectl exec -it vault-0 -n vault -- /bin/sh
```

Set the root token generated in Step 7:

```bash
export VAULT_TOKEN=<new-root-token-from-step-7>
```

Restore the snapshot:

```bash
vault operator raft snapshot restore -force /tmp/restore.snap
```

> The `-force` flag is required because the encryption key generation of the newly initialized Vault is different from the encryption key generation contained in the snapshot.

### ⑩ Step 10: Verify That Vault Has Automatically Unsealed Again

After the restore operation, Vault will temporarily become sealed again and should automatically unseal itself because the restored data was previously encrypted using the same small Vault (KMS):

```bash
kubectl exec -it vault-0 -n vault -- vault status
```

Wait a few seconds if necessary and check again.

You should see:

```text
Sealed: false
```

**without entering any keys.**

### ⑪ Step 11: Join the Other Pods to the Raft Cluster

Join `vault-1` to the Raft cluster:

```bash
kubectl exec -it vault-1 -n vault -- vault operator raft join http://vault-0.vault-internal:8200
```

Join `vault-2` to the Raft cluster:

```bash
kubectl exec -it vault-2 -n vault -- vault operator raft join http://vault-0.vault-internal:8200
```

These pods should also automatically unseal without requiring keys because all of them use the same KMS.

### ⑫ Step 12: Final Verification

Check the Vault pods:

```bash
kubectl get pods -n vault
```

All three pods should be:

```text
2/2 Running
```

Verify that the actual Vault data has been successfully restored:

```bash
kubectl exec -it vault-0 -n vault -- vault kv get kv/org/panel-admin
```

The output should contain the **same old `created_time` and the original secret value**, rather than a newly created version.

### ⑬ Step 13: Restart Dependent Applications

Restart the applications that depend on Vault:

```bash
kubectl delete pod -n panel-admin -l app=panel-admin-dep
```

Then verify the pods:

```bash
kubectl get pods -n panel-admin
```

Each pod should eventually reach:

```text
2/2 Running
```

## 🟢 Important Findings from the Real Recovery Test

- **If only the namespace is deleted but the physical NFS data is not deleted**, the new Vault instance will connect to the old data and will not require a restore at all. This is **not a real "complete loss" test**; it is only a restart scenario.

- **The `.snap` file cannot be booted directly.** It can only be used through the `vault operator raft snapshot restore` command, which performs an API call against a running Vault instance. The snapshot cannot simply be placed directly on disk with the expectation that Vault will boot from it.

- Before migrating to Auto-Unseal, this recovery process required the five old Shamir keys together with the `-migrate` flag. After implementing Auto-Unseal, as described in **Report 2**, this requirement was completely removed.
