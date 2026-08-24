## 🎯 Complete Guide: Moving a Connection String from a ConfigMap into Vault

**📍  Purpose of this document:**  This is a generic, self-contained runbook. Any engineer who needs to pull a connection string (or any other secret) out of a ConfigMap and store it securely in Vault should be able to follow this document alone, for any new application on the cluster, without needing help from anyone else.

Throughout this document, placeholders that must be replaced with your own app's information are marked with `<...>`. To make things concrete, a real example application called `panel-admin` is shown alongside each one.

|                     |                                           |                      |
| ------------------- | ----------------------------------------- | -------------------- |
| `<APP_NAME>`        | Application name                          | `panel-admin`        |
| `<NAMESPACE>`       | The app's namespace on the cluster        | `panel-admin`        |
| `<SERVICE_ACCOUNT>` | Dedicated ServiceAccount name for the app | `panel-admin-vault`  |
| `<VAULT_POLICY>`    | Policy name in Vault                      | `panel-admin-policy` |
| `<VAULT_ROLE>`      | Role name in Vault                        | `panel-admin`        |
| `<SECRET_PATH>`     | Path where the secret is stored in KV     | `org/panel-admin`    |
| `<CONFIGMAP_NAME>`  | The app's current ConfigMap               | `panel-admin-cm`     |
| `<CONNECTION_KEY>`  | The key for the connection string         | `DefaultConnection`  |

---

### 🟢 Prerequisites

This document assumes:

- A Vault cluster (HA, three nodes, Raft storage) is already installed and has been **initialized and unsealed**.
- You have access to the Root Token, or a token with sufficient management permissions (policy write, auth, role).
- Vault Agent Injector is already enabled on the cluster (this is part of the base Vault installation and does not need to be repeated per app).

If any of these prerequisites are not in place, Vault itself must first be installed and set up — this document only covers the step of *adding a new application* to an existing Vault.

---

## ① Step 1: Locate the current connection string in the ConfigMap

```
kubectl get configmap <CONFIGMAP_NAME> -n <NAMESPACE> -o yaml
```

Inside the output, look for the `appsettings.json` section (or whatever config file your app uses) and copy the value of the connection string you want to migrate. For example, something like this:

```
{
  "ConnectionStrings": {
    "DefaultConnection": "data source=xxxxx.com,12544;initial catalog=MyDb;user id=test;password=xxxxx;..."
  }
}
```

---

## ② Step 2: Log into Vault

```
kubectl exec -it vault-0 -n vault -- /bin/sh
```

```
export VAULT_TOKEN=<your-root-or-management-token>
```

From here on, all commands in this section are run inside this shell (inside the `vault-0` pod).

---

## ③ Step 3: Make sure the KV v2 secrets engine is enabled

```
vault secrets list -detailed
```

If you see a line with path `kv/` and `version=2`, skip this step (this engine is shared across all apps and is only created once for the whole Vault). If not:

```
vault secrets enable -path=kv -version=2 kv
```

---

## ④ Step 4: Create the secret in Vault

```
vault kv put kv/<SECRET_PATH> <CONNECTION_KEY>='<the-connection-string-value-you-copied-in-step-1>'
```

Real example:

```
vault kv put kv/org/panel-admin DefaultConnection='data source=orgapp-db-test.acctechco.com,12544;initial catalog=PanelAdminDb;user id=PORTALADMIN;password=xxxxx;...'
```

Verify it was saved:

```
vault kv get kv/<SECRET_PATH>
```

> **Note:** For KV version 2, the path you use in the CLI/UI (`kv/<SECRET_PATH>`) differs from the path used in policies/injector annotations (`kv/data/<SECRET_PATH>`) — the word `data` is inserted between the two. This distinction causes mistakes very often, so keep this table handy:

|                                 |                         |
| ------------------------------- | ----------------------- |
| Vault CLI (`vault kv put/get`)  | `kv/<SECRET_PATH>`      |
| Vault UI| `kv/<SECRET_PATH>`      |
| Vault Policy                    | `kv/data/<SECRET_PATH>` |
| Vault Agent Injector annotation | `kv/data/<SECRET_PATH>` |

---

## ⑤ Step 5: Create a restricted policy

We only grant read access (not write, not list) to that one specific path — nothing more.

```
cat > /tmp/<VAULT_POLICY>.hcl << 'EOF'
path "kv/data/<SECRET_PATH>" {
  capabilities = ["read"]
}
EOF
```

> ⚠️ Always use the `cat > ... << 'EOF'` method, not `vi`. If you do use `vi`, make sure you press `i` first to enter insert mode — otherwise the first characters you type get interpreted as commands instead of text, and the file ends up corrupted (this is a very common mistake).

Load it into Vault:

```
vault policy write <VAULT_POLICY> /tmp/<VAULT_POLICY>.hcl
```

Verify:

```
vault policy read <VAULT_POLICY>
```

---

## ⑥ Step 6: Enable Kubernetes Auth (only once, for the whole Vault)

```
vault auth list
```

If `kubernetes/` is already in the list, skip this step and go to Step 7 (like KV, this is created once for the whole Vault, not per app). If not:

```
vault auth enable kubernetes
```

```
echo $KUBERNETES_SERVICE_HOST
echo $KUBERNETES_SERVICE_PORT
```

```
vault write auth/kubernetes/config kubernetes_host="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
```

---

## ⑦ Step 7: Create the Role for this app

**⚠️ This is the step that is most often forgotten, and it's the cause of the ****`invalid role name`**** error. Without this step, Vault Agent can never log in.**

```
vault write auth/kubernetes/role/<VAULT_ROLE> \
  bound_service_account_names=<SERVICE_ACCOUNT> \
  bound_service_account_namespaces=<NAMESPACE> \
  policies=<VAULT_POLICY> \
  ttl=1h
```

Real example:

```
vault write auth/kubernetes/role/panel-admin \
  bound_service_account_names=panel-admin-vault \
  bound_service_account_namespaces=panel-admin \
  policies=panel-admin-policy \
  ttl=1h
```

Verify (this is not an optional step — always do it):

```
vault read auth/kubernetes/role/<VAULT_ROLE>
```

The output should show `bound_service_account_names`, `bound_service_account_namespaces`, and `token_policies` with the correct values. If you see `No value found`, it means the command above either didn't run or failed — go back and run it again.

From here on, exit the Vault pod's shell (`exit`) and continue on the main cluster terminal.

---

## ⑧ Step 8: Create a dedicated ServiceAccount for the application

Every application should have its own dedicated ServiceAccount (not the namespace's default one):

```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: <SERVICE_ACCOUNT>
  namespace: <NAMESPACE>
```

Save this file (e.g. `<app-name>-serviceaccount.yaml`) and apply it:

```
kubectl get ns <NAMESPACE> || kubectl create namespace <NAMESPACE>
kubectl apply -f <app-name>-serviceaccount.yaml
```

---

## ⑨ Step 9: Configure the application Deployment

Three changes need to be made to the application's Deployment:

### 9.1 — Vault Agent Injector annotations

These must go under `spec.template.metadata.annotations` — **not** under the top-level `metadata` at the top of the file (this is also a common mistake):

```
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "<VAULT_ROLE>"
        vault.hashicorp.com/agent-inject-secret-db: "kv/data/<SECRET_PATH>"
        vault.hashicorp.com/agent-inject-template-db: |
          {{- with secret "kv/data/<SECRET_PATH>" -}}
          export ConnectionStrings__<CONNECTION_KEY>="{{ .Data.data.<CONNECTION_KEY> }}"
          {{- end }}
```

### 9.2 — Use the ServiceAccount you created

```
spec:
  template:
    spec:
      serviceAccountName: <SERVICE_ACCOUNT>
```

### 9.3 — Load the environment variable before the application starts

Vault Agent writes the secret's value into a file called `/vault/secrets/db` (you can change the name `db` in the annotation above). The application must source this file before starting:

```
containers:
  - name: <app-name>-con
    command:
      - /bin/sh- -c
    args:
      - |
        . /vault/secrets/db
        exec <your-application's-actual-start-command>
```

> For `.NET` apps, the actual start command is usually something like `dotnet AppName.Web.dll`. For Node.js it's usually something like `node index.js`, etc. — replace this with whatever is in your Docker image's `ENTRYPOINT`/`CMD`.

---

## ⑩ Step 10: Remove the connection string from appsettings.json/ConfigMap

This is the last and most important step for security — if you skip this, the secret still exists in two places (plaintext in the ConfigMap, and encrypted in Vault), which defeats the entire purpose of this exercise.

Before:

```
{
  "ConnectionStrings": {
    "<CONNECTION_KEY>": "data source=...;password=..."
  }
}
```

After:

```
{
  "ConnectionStrings": {
  }
}
```

Update the ConfigMap with the new content (without the connection string):

```
kubectl create configmap <CONFIGMAP_NAME> --from-file=appsettings.json -n <NAMESPACE> --dry-run=client -o yaml | kubectl apply -f -
```

---

## ⑪ Step 11: Apply and test the Deployment

```
kubectl apply -f <app-name>-deployment.yaml
```

```
kubectl get pods -n <NAMESPACE>
```

Every pod should become `2/2 Running` (the main container plus the Vault Agent sidecar). If it stays at `1/2` or goes into `CrashLoopBackOff`, see the "Troubleshooting" section below.

Verify the secret was actually injected:

```
kubectl exec -it <pod-name> -n <NAMESPACE> -c <app-name>-con -- ls -la /vault/secrets/
```

You should see a file named `db`.

Verify the environment variable was loaded correctly:

```
kubectl exec -it <pod-name> -n <NAMESPACE> -c <app-name>-con -- \
  test -n "$ConnectionStrings__<CONNECTION_KEY>" && echo "Vault connection string loaded" || echo "NOT loaded"
```

> ⚠️ Never run or paste the output of `cat /vault/secrets/db` in production, logs, or tickets — it exposes the real database password.

---

## 📍 📍  Troubleshooting: Common Errors

### Error: `invalid role name "<VAULT_ROLE>"`

**Cause:** Step 7 (creating the Role) was skipped, or the role name doesn't match the [`vault.hashicorp.com/role`](http://vault.hashicorp.com/role) annotation in the Deployment.

**Fix:**

```
kubectl exec -it vault-0 -n vault -- vault read auth/kubernetes/role/<VAULT_ROLE>
```

If it returns `No value found`, go back and run Step 7. After creating the role, restart the application's pod so the sidecar retries:

```
kubectl delete pod -n <NAMESPACE> -l app=<app-label>
```

### Error: `permission denied` when reading the secret

**Common cause:** The policy has the wrong path (remember, the policy must use `kv/data/...`, not `kv/...`), or the policy name in the role is misspelled.

**Fix:**

```
vault policy read <VAULT_POLICY>
vault read auth/kubernetes/role/<VAULT_ROLE>
```

Compare the path inside the policy with the policy name inside the role.

### Error: `path is already in use` when enabling a secrets engine or auth method

This is not an error — it just means it was already enabled (e.g. `kv/` or `kubernetes/`). This step only needs to be done once for the whole Vault, not per app — skip it and continue.

### Policy file fails to parse (e.g. `invalid key "th"`)

**Cause:** The file was created with `vi`, but insert mode (`i`) wasn't entered before typing, so the first few characters were interpreted as commands instead of being typed into the file.

**Fix:** Always use the heredoc method from Step 5, not `vi`.

### Pod stays at `1/2` and doesn't restart, but Vault itself isn't sealed

This is related to the Vault Agent Injector for this specific app, not the overall Vault setup — check the sidecar's logs:

```
kubectl logs <pod-name> -n <NAMESPACE> -c vault-agent
```

You will usually see one of the two errors above in this log.

---

### 🟢 Quick-Reference Checklist

- Connection string copied from the existing ConfigMap
- KV v2 engine is enabled (once per Vault)
- Secret created with `vault kv put kv/<SECRET_PATH>`
- Policy created with read-only access to `kv/data/<SECRET_PATH>`
- Kubernetes Auth is enabled (once per Vault)
- **Role created for this specific app** (the most commonly forgotten step)
- Dedicated ServiceAccount created on the cluster
- Injector annotations added under `template.metadata.annotations`
- `serviceAccountName` set in the Deployment
- `command`/`args` updated to source `/vault/secrets/db`
- Connection string removed from appsettings.json/ConfigMap
- Pod reached `2/2`, and both the `/vault/secrets/db` file and the environment variable were verified

---

### 🟢 Security Notes

- For day-to-day operations (not just initial setup), use a token with a restricted management policy instead of the Root Token.
- Every app should have its own dedicated Policy and Role — never share a single Role/Policy across multiple apps, since that would let each app read every other app's secrets too.
- To rotate the database password later, simply run `vault kv put` again with the new value (a new version is created) and restart the application's pod — no Deployment changes are needed.
