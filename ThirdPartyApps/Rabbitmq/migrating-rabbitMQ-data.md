## Work Report: Migrating RabbitMQ Definitions Between Two Kubernetes Clusters (via NFS + ConfigMap)

### 🎯 Summary

A RabbitMQ instance was running in **Cluster A**. A new RabbitMQ deployment was required in **Cluster B**, but it needed to start with the **same operational configuration** (users, vhosts, and permissions) as the existing environment.
Instead of transferring the full broker state (queues/messages), the approach used a controlled **export of RabbitMQ definitions**, persisted the export via an **existing NFS-backed mount**, and then bootstrapped the new RabbitMQ instance in Cluster B by mounting the exported definitions using a **ConfigMap** and enabling `load_definitions` on startup.

---

## 🔹 Objectives

* Reuse RabbitMQ configuration from Cluster A in Cluster B:

  * **Users**
  * **Virtual hosts (vhosts)**
  * **Permissions**
* Avoid transferring large broker state and reduce operational risk.
* Use storage already available and reliable (**NFS**).
* Ensure the new RabbitMQ instance in Cluster B starts correctly with the required definitions **from day one**.

---

## 🔹 Implementation Details

### 📌 1) Exporting RabbitMQ definitions in Cluster A

The export was generated from inside the **RabbitMQ Pod**. The standard RabbitMQ export command is:

```bash
rabbitmqctl export_definitions /tmp/rabbitmq-definitions.json
```

(If the binary is not on PATH in some images, it can be invoked from the RabbitMQ installation directory, e.g. Bitnami-based containers.)

This produced a full definitions file including:

* users, vhosts, permissions
* exchanges, queues, bindings
* and other broker configuration elements

---

### 📌 2) Persisting the export on NFS (via the existing volume mount)

To avoid large file transfer directly from the Pod, the exported JSON was moved into the **mounted persistent path** so it would be stored on NFS.

The mounted path used by the RabbitMQ container was:

* `mountPath`:
  `/opt/bitnami/rabbitmq/.rabbitmq/mnesia`

This ensured the file was written to NFS-backed storage and could be accessed externally from the NFS VM or other infrastructure nodes.

---

### 📌 3) Moving the exported file to the target environment

After the file was available on the NFS side, it was copied to the administrative host in Cluster B (Kubernetes master/management VM) for processing and deployment.

Example location used in Cluster B admin host:

* `/home/atadmin/rabbitmq-definitions.json`

---

### 📌 4) Reducing the definitions file to only the required configuration

The complete definitions export contained many objects that were not required for the bootstrap in Cluster B. Only the following sections were needed:

* `users`
* `vhosts`
* `permissions`

A filtered bootstrap file was created using `jq`:

```bash
jq '{
  users,
  vhosts,
  permissions
}' rabbitmq-definitions.json > rabbitmq-definitions-bootstrap.json
```

This reduced the file size and focused the bootstrap strictly on the required authorization and tenancy structure.

---

### 📌 5) Creating a ConfigMap in Cluster B and loading definitions on startup

The filtered JSON was stored in Kubernetes as a ConfigMap in the target namespace (RabbitMQ namespace):

```bash
kubectl -n rabbit create configmap rabbitmq-definitions \
  --from-file=rabbitmq-definitions.json
```

### 📌 6) mount ConfigMap 

Then the RabbitMQ Helm deployment was configured to:

1. mount the ConfigMap file into the RabbitMQ container
2. instruct RabbitMQ to load definitions at startup

Key Helm override configuration (as implemented):

```yaml
extraVolumes:
  - name: rabbitmq-definitions
    configMap:
      name: rabbitmq-definitions

extraVolumeMounts:
  - name: rabbitmq-definitions
    mountPath: /app/rabbitmq-definitions.json
    subPath: rabbitmq-definitions.json
    readOnly: true

extraConfiguration: |-
  ## Load users / vhosts / permissions / policies
  load_definitions = /app/rabbitmq-definitions.json
```

🟢 With this configuration, the new RabbitMQ instance in Cluster B bootstraps automatically with the required users/vhosts/permissions on first start.

---

## 📍📍📍 Persistence and Storage Configuration (Cluster B)

RabbitMQ persistence remained enabled and continued using NFS:

```yaml
persistence:
  enabled: true
  storageClass: k8s-test-nfs
  mountPath: /opt/bitnami/rabbitmq/.rabbitmq/mnesia
  subPath: rabbit-data
```

This ensures RabbitMQ state is durable and aligned with the existing storage strategy.

---
