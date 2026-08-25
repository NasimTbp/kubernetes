# Setting Up Transit Auto-Unseal (`vault-unseal`)

## 🎯 Why We Did This

By default, Vault uses the Shamir algorithm: the master encryption key is not stored anywhere (neither on disk nor in the code). Instead, it is split among 5 people, and every time Vault restarts (pod restart, node restart, rolling update), 3 out of those 5 people must simultaneously enter their respective keys for Vault to become unsealed again.

This design is intentional and is meant for security (no individual or system should be able to access all the data on its own), but it creates a serious operational problem: **every time any Vault pod restarts, a human must be present and manually enter the key.** In a production environment with frequent rolling updates, node restarts, or no personnel available during off-hours, this dependency can cause the service to become unavailable.

**The industry-standard solution:** Auto-Unseal — instead of relying on 5 people, the master encryption key is managed by a trusted external system (KMS). The most common options are AWS KMS, GCP Cloud KMS, Azure Key Vault, or a physical HSM. Since our environment is completely on-premise and has no cloud infrastructure, we used **Transit Auto-Unseal**: a small, separate Vault (`vault-unseal`) that only acts as a KMS, while the main Vault (three-node) uses it to automatically unseal itself.

> Honest note: This method does not eliminate the "need for a human"; it simply moves that dependency from the main Vault (which restarts frequently) to a small, stable Vault (which rarely restarts).

## 🟢 Architecture

```text
Main Vault (three-node, Raft HA)

    │
    │  At startup: "Unwrap my key"
    ▼

vault-unseal (small, single-node Vault)

    │

    └── Transit engine with a key named autounseal
```

## 🟢 Implementation Steps

### Ⓐ Phase A: Installing the Small Vault Dedicated to KMS

The small Vault was installed using the same Helm chart (`hashicorp/vault`) version `0.34.0`, but with simpler configuration:

* Single-node (`standalone`), not HA
* `injector.enabled: false` (it does not need to inject secrets into applications)
* Without an Istio sidecar (`sidecar.istio.io/inject: "false"`) — because this is an internal backend service, not part of application traffic
* Storage of type `file` (not Raft) on a small PVC (2 GB)

Installation was performed through a separate Argo CD Application (`vault-unseal`) in a separate namespace (`vault-unseal`), using a manually created PersistentVolume (static provisioning) on the same main NFS server, following the existing pattern already used in the cluster.

### Ⓑ Phase B: Setting Up the Transit Engine

Inside the small Vault:

```bash
kubectl exec -it vault-unseal-0 -n vault-unseal -- /bin/sh

export VAULT_TOKEN=<small Vault root token>

vault secrets enable transit

vault write -f transit/keys/autounseal
```

A restricted policy was created that only allows encrypt/decrypt operations on this specific key:

```hcl
cat > /tmp/autounseal-policy.hcl << 'EOF'

path "transit/encrypt/autounseal" {

  capabilities = ["update"]

}

path "transit/decrypt/autounseal" {

  capabilities = ["update"]

}

EOF

vault policy write autounseal-policy /tmp/autounseal-policy.hcl
```

A permanent (periodic) token with this policy was created for the main Vault to use:

```bash
vault token create -policy=autounseal-policy -period=768h -orphan
```

This token was stored as a Kubernetes Secret in the `vault` namespace (where the main Vault is running):

```bash
kubectl create secret generic vault-unseal-token -n vault --from-literal=VAULT_TOKEN=<token>
```

### Ⓒ Phase C: Connecting the Main Vault to This KMS

Two changes were made to the main `override.yaml` file (`argo-sync/helm/override.yaml`):

**1. Injecting the token as an environment variable:**

```yaml
extraSecretEnvironmentVars:
  - envName: VAULT_TOKEN
    secretName: vault-unseal-token
    secretKey: VAULT_TOKEN
```

**2. Adding the `seal "transit"` block to the Raft configuration, before `listener "tcp"`:**

```yaml
ha:
  raft:
    config: |
      ui = true
      seal "transit" {address         = "http://vault-unseal.vault-unseal.svc:8200"
        disable_renewal = "false"
        key_name        = "autounseal"
        mount_path      = "transit/"
      }
      listener "tcp" {
        tls_disable     = 1
        address         = "[::]:8200"
        cluster_address = "[::]:8201"
      }
      ...
```

### Ⓓ Phase D: Actual Migration (Shamir → Transit)

After this change was committed/pushed to Git and synchronized by Argo, the old pods had to be manually deleted (because `updateStrategyType: OnDelete` is configured):

```bash
kubectl delete pod vault-0 vault-1 vault-2 -n vault
```

After they came back up, the `vault-0` logs showed the following line, confirming that the migration had started:

```text
core: entering seal migration mode; from_barrier_type=shamir to_barrier_type=transit
```

The migration was completed using 3 of the **original and old** keys (which had previously been obtained from the first `vault operator init`) and with the mandatory `-migrate` flag:

```bash
kubectl exec -it vault-0 -n vault -- vault operator unseal -migrate <first key>

kubectl exec -it vault-0 -n vault -- vault operator unseal -migrate <second key>

kubectl exec -it vault-0 -n vault -- vault operator unseal -migrate <third key>
```

> Note: The first attempt was made without the `-migrate` flag and resulted in the error `migrate option not provided and seal migration is pending`. This flag is mandatory for every seal migration.

## 🟢 Successful Verification

```bash
kubectl exec -it vault-0 -n vault -- vault status
```

Key output:

```text
Seal Type              transit

Recovery Seal Type     shamir

Sealed                 false
```

The most important test was `vault-1` and `vault-2` — no keys were provided to them, yet they automatically reached `2/2 Running` because they were automatically unsealed through `vault-unseal`.

**The final definitive test:** One pod was manually deleted:

```bash
kubectl delete pod vault-1 -n vault
```

Without running any unseal command, it automatically returned to `2/2 Running` in approximately 25 seconds.

## Important Note About the Dependency

Once the main Vault has successfully been unsealed, it no longer needs `vault-unseal` during normal operations (reading/writing secrets) — the encryption key remains in the live memory of the main Vault. `vault-unseal` is only required again at the moment of **startup** (pod restart, node restart, etc.).

If `vault-unseal` goes down while the main Vault is running, there is no service disruption — the problem only occurs if one of the main Vault pods also restarts at the same time.
