# RabbitMQ User Creation Guide

This document explains how to:

1. Generate a password hash for RabbitMQ
2. Add a new user inside `rabbitmq-definitions.json`
3. Apply the configuration inside Kubernetes

---

## 1️⃣ Generate Password Hash

RabbitMQ does NOT accept plain text passwords inside `definitions.json`.

You must generate a SHA256 hash.

### Option 1 (Recommended) – Inside RabbitMQ Pod

```bash
kubectl exec -it <rabbitmq-pod-name> -- rabbitmqctl hash_password "RbTPaSvorDForTheSErvice"
```

Example output:

```
XyZabc123GeneratedHashValue==
```

Copy this value.  
This will be used as `password_hash`.

Make sure hashing algorithm is:
```
rabbit_password_hashing_sha256
```

---

## 2️⃣ Add User to rabbitmq-definitions.json

Open your ConfigMap or definitions file and add the new user inside the `"users"` array.

Example:

```
{
  "users": [
    {
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "limits": {},
      "name": "srmgateway",
      "password_hash": "hfTA5a980A1nfSypFbMCypvzoEn9o9NWaLhT8y+2b1XjwU",
      "tags": ["management"]
    },
    {
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "limits": {},
      "name": "fleetmgmtHF",
      "password_hash": "XyZabc123GeneratedHashValue", // the generated password hash
      "tags": ["management"]
    }
  ],
  "permissions": [
    
  ]
}
```

Replace `PASTE_GENERATED_HASH_HERE` with the generated hash.

---

## 3️⃣ Add permissions to rabbitmq-definitions.json

Open your ConfigMap or definitions file and add the new permission inside the `"permissions"` array.

Example:

```json
{
  "permissions": [
    {
      "configure": ".*",
      "read": ".*",
      "user": "srmgateway",
      "vhost": "/",
      "write": ".*"
    },
    {
      "configure": ".*",
      "read": ".*",
      "user": "fleetmgmtHF",
      "vhost": "/",
      "write": ".*"
    }
  ]
}
```

Replace `PASTE_GENERATED_HASH_HERE` with the generated hash.

---

## 4️⃣ Apply Changes in Kubernetes

If you updated a ConfigMap:

```bash
kubectl apply -f your-configmap.yaml
```

Then restart RabbitMQ:

```bash
kubectl rollout restart statefulset <rabbitmq-statefulset-name>
```

---

## ⚠️ Important Notes

- Definitions are usually loaded only at startup.
- If the user already exists, it may not be overwritten.
- Storing password hashes in ConfigMap is NOT secure.
- For production environments, use:
    - Kubernetes Secret
    - External Secret Manager (Vault, etc.)

---

## ✅ Summary

Steps:

1. Generate password hash
2. Add user entry inside JSON
3. Apply ConfigMap
4. Restart RabbitMQ

Done.
