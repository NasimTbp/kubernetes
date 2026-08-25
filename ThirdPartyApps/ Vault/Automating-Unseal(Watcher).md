# 🎯 Automating Unseal for `vault-unseal` Itself (Watcher)

## ⚠️ Problem

After setting up Transit Auto-Unseal (Report 2), all restarts of the main Vault (three-node) are handled without human intervention. However, one weak point remained: `vault-unseal` itself (the small Vault acting as the KMS) is also a regular Vault with Shamir sealing — meaning that if it restarts (crash, node restart, or any other reason), it remains locked (Sealed) and waits for a human to manually provide 3 keys.

The concern raised was: **"What if no one is available and this pod gets restarted? What happens then?"** — because in that situation, if one of the main Vault pods also restarts at the same time, it can no longer automatically unseal itself (because the KMS behind it is also locked).

## 🟢 Security Decision and Trade-off

Two options were considered:

| Option | Advantage | Disadvantage |
|---|---|---|
| Prevent restarts (PodDisruptionBudget, pinning to a fixed node) | The Shamir philosophy (requiring multiple people) remains intact | Rare and unexpected restarts are still not addressed |
| Store the keys in a Secret and automatically unseal | Zero human intervention, even for rare restarts | Anyone with access to this Secret can independently bypass the entire security chain |

**Final decision:** The second option was chosen — and this document records that this was an intentional decision made with awareness and acceptance of the associated security risk.

## 🟢 Implementation

### ① Step 1: Storing the Three Keys in a Secret

Of the 5 Unseal keys obtained when running `vault operator init` for `vault-unseal`, only 3 keys (the minimum required to reach the threshold) were stored in a Secret — not all 5, in order to minimize the exposure scope in case of a leak:

```bash
kubectl create secret generic vault-unseal-selfkeys -n vault-unseal \
  --from-literal=key1=<first key> \
  --from-literal=key2=<second key> \
  --from-literal=key3=<third key>
````

### ② Step 2: Creating a Watcher Deployment

A small, always-running pod was created that checks the status of `vault-unseal` every 15 seconds and automatically performs an unseal if it is sealed.

```yaml
apiVersion: apps/v1
kind: Deployment

metadata:
  name: vault-unseal-watcher
  namespace: vault-unseal

spec:
  replicas: 1

  selector:
    matchLabels:
      app: vault-unseal-watcher

  template:
    metadata:
      labels:
        app: vault-unseal-watcher
      annotations:
        sidecar.istio.io/inject: "false"

    spec:
      containers:
        - name: watcher
          image: repo.acctechco.com:8444/hashicorp/vault:1.18.3

          command:
            - /bin/sh
            - -c

          args:
            - |
              export VAULT_ADDR="http://vault-unseal.vault-unseal.svc:8200"

              while true; do

                # Exit code of the vault status command:
                # 0 = unsealed and healthy, 2 = sealed, 1 = other error (e.g. inaccessible)

                vault status >/tmp/status.out 2>&1
                CODE=$?

                if [ "$CODE" -eq 2 ]; then
                  echo "$(date) - vault-unseal is SEALED, applying keys..."

                  vault operator unseal "$UNSEAL_KEY_1"
                  vault operator unseal "$UNSEAL_KEY_2"
                  vault operator unseal "$UNSEAL_KEY_3"

                  echo "$(date) - unseal attempt done."

                elif [ "$CODE" -eq 0 ]; then
                  echo "$(date) - vault-unseal is healthy."

                else
                  echo "$(date) - could not reach vault-unseal (exit code $CODE), will retry."
                fi

                sleep 15
              done

          env:
            - name: UNSEAL_KEY_1
              valueFrom:
                secretKeyRef:
                  name: vault-unseal-selfkeys
                  key: key1

            - name: UNSEAL_KEY_2
              valueFrom:
                secretKeyRef:
                  name: vault-unseal-selfkeys
                  key: key2

            - name: UNSEAL_KEY_3
              valueFrom:
                secretKeyRef:
                  name: vault-unseal-selfkeys
                  key: key3

          resources:
            requests:
              memory: 32Mi
              cpu: 25m

            limits:
              memory: 64Mi
              cpu: 50m
```

```bash
kubectl apply -f vault-unseal-watcher.yaml
```

## 🟢 Problem Encountered During the First Test and Its Resolution

The first version of the watcher extracted the `sealed` status using `grep`/`cut` from the output of `vault status -format=json`:

```sh
SEALED=$(vault status -format=json 2>/dev/null | grep -o '"sealed":[a-z]*' | cut -d: -f2)
```

This approach failed because Vault's JSON output uses pretty-print formatting and puts a space after `:` (for example, `"sealed": true`), while the `grep` pattern did not account for the space. As a result, the `SEALED` variable always remained empty and the watcher assumed the Vault was healthy, even though it was actually sealed — and it never actually performed the unseal, without showing any errors either.

**Solution:** Instead of parsing JSON text (which is sensitive to the output format and therefore fragile), the **exit code** of the `vault status` command was used, which is always precise and reliable:

* `0` = unsealed and healthy
* `2` = sealed
* `1` or anything else = access/error issue

This change completely resolved the problem.

## 🟢 Testing and Verification

The `vault-unseal-0` pod was manually deleted:

```bash
kubectl delete pod vault-unseal-0 -n vault-unseal
```

Without running any manual unseal command, the watcher logs showed:

```text
... - vault-unseal is SEALED, applying keys...

... - unseal attempt done.
```

And the `vault-unseal-0` pod automatically reached `1/1 Running` (healthy).

## 🟢 Final Architecture Summary

```text
vault-unseal-watcher (checks every 15 seconds)
        │
        ▼
   vault-unseal-0  ──(auto-unseal)──▶️  vault-0/1/2 (Main Vault)
        │
        └── If it becomes sealed itself, the watcher automatically unseals it using 3 keys
```

With these three layers (Main Vault HA + Transit Auto-Unseal + Automatic Watcher), the only scenario that still requires human intervention is the complete and simultaneous loss of both the main Vault and its NFS infrastructure — which, according to the deliberate decision, was intentionally not automated.
