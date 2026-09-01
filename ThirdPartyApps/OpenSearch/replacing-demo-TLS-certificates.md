# OpenSearch — Replacing Demo TLS Certificates

**Cluster:** `opensearch-logs` (namespace: `observability`)
**Date:** 2026-07-11

## Why

The chart ships with publicly known demo certificates
(`kirk.pem`, `root-ca.pem`, etc.) whose private keys are published in the
OpenSearch project's public repository. Anyone with network access to the
cluster could decrypt traffic or impersonate a node. These must be replaced
before the cluster is trusted with real data.

## Step 1 — Generate a private CA and certificates

Performed on a workstation, **not** inside the cluster:

```bash
mkdir -p ~/opensearch-certs && cd ~/opensearch-certs
```

**Root CA:**

```bash
openssl genrsa -out root-ca-key.pem 2048
openssl req -new -x509 -sha256 -key root-ca-key.pem -out root-ca.pem -days 3650 \
  -subj "/C=IR/O=AccTechCo/CN=opensearch-root-ca"
```

**Admin certificate** (used for `securityadmin.sh` / admin-level auth):

```bash
openssl genrsa -out admin-key-temp.pem 2048
openssl pkcs8 -inform PEM -outform PEM -in admin-key-temp.pem -topk8 -nocrypt -v1 PBE-SHA1-3DES -out admin-key.pem
openssl req -new -key admin-key.pem -out admin.csr -subj "/C=IR/O=AccTechCo/CN=admin"
openssl x509 -req -in admin.csr -CA root-ca.pem -CAkey root-ca-key.pem -CAcreateserial \
  -sha256 -out admin.pem -days 3650
```

**Node certificate** (shared by all 3 pods — SAN must cover every hostname
the pods and services use):

Checked actual service names first:

```bash
kubectl get svc -n observability
```

```
NAME                              TYPE        CLUSTER-IP      PORT(S)
opensearch-logs-master            ClusterIP   10.233.37.170   9200/TCP,9300/TCP,9600/TCP
opensearch-logs-master-headless   ClusterIP   None            9200/TCP,9300/TCP,9600/TCP
```

Created the SAN extension file:

```bash
cat > node.ext <<'EOF'
subjectAltName = @alt_names
[alt_names]
DNS.1 = opensearch-logs-master-0
DNS.2 = opensearch-logs-master-1
DNS.3 = opensearch-logs-master-2
DNS.4 = opensearch-logs-master
DNS.5 = opensearch-logs-master-headless
DNS.6 = opensearch-logs-master.observability.svc
DNS.7 = opensearch-logs-master.observability.svc.cluster.local
DNS.8 = localhost
IP.1 = 127.0.0.1
EOF
```

Generated the node key and certificate:

```bash
openssl genrsa -out node-key-temp.pem 2048
openssl pkcs8 -inform PEM -outform PEM -in node-key-temp.pem -topk8 -nocrypt -v1 PBE-SHA1-3DES -out node-key.pem
openssl req -new -key node-key.pem -out node.csr -subj "/C=IR/O=AccTechCo/CN=opensearch-logs-master"
openssl x509 -req -in node.csr -CA root-ca.pem -CAkey root-ca-key.pem -CAcreateserial \
  -sha256 -out node.pem -days 3650 -extfile node.ext
```

Verified the SAN list was correctly embedded:

```bash
openssl x509 -in node.pem -noout -text | grep -A1 "Subject Alternative Name"
```

```
X509v3 Subject Alternative Name:
    DNS:opensearch-logs-master-0, DNS:opensearch-logs-master-1, DNS:opensearch-logs-master-2,
    DNS:opensearch-logs-master, DNS:opensearch-logs-master-headless,
    DNS:opensearch-logs-master.observability.svc,
    DNS:opensearch-logs-master.observability.svc.cluster.local,
    DNS:localhost, IP Address:127.0.0.1
```

Files produced: `root-ca.pem`, `admin.pem`, `admin-key.pem`, `node.pem`, `node-key.pem`.

## Step 2 — Create the Kubernetes Secret

```bash
kubectl create secret generic opensearch-certs -n observability \
  --from-file=root-ca.pem=root-ca.pem \
  --from-file=admin.pem=admin.pem \
  --from-file=admin-key.pem=admin-key.pem \
  --from-file=node.pem=node.pem \
  --from-file=node-key.pem=node-key.pem
```

Verified:

```bash
kubectl get secret -n observability
```

```
NAME                      TYPE     DATA   AGE
opensearch-admin-secret   Opaque   1      4h19m
opensearch-certs          Opaque   5      63s
```

## Step 3 — Mount the Secret and Update `opensearch.yml`

Added to `override.yaml`:

```yaml
extraVolumes:
  - name: custom-certs
    secret:
      secretName: opensearch-certs

extraVolumeMounts:
  - name: custom-certs
    mountPath: /usr/share/opensearch/config/custom-certs
    readOnly: true
```

Added TLS settings to `config.opensearch.yml`:

```yaml
config:opensearch.yml: |-
    # ... existing settings unchanged ...

    # TLS transport (between nodes, port 9300)
    plugins.security.ssl.transport.pemcert_filepath: custom-certs/node.pem
    plugins.security.ssl.transport.pemkey_filepath: custom-certs/node-key.pem
    plugins.security.ssl.transport.pemtrustedcas_filepath: custom-certs/root-ca.pem
    plugins.security.ssl.transport.enforce_hostname_verification: false

    # TLS for REST API (port 9200)
    plugins.security.ssl.http.enabled: true
    plugins.security.ssl.http.pemcert_filepath: custom-certs/node.pem
    plugins.security.ssl.http.pemkey_filepath: custom-certs/node-key.pem
    plugins.security.ssl.http.pemtrustedcas_filepath: custom-certs/root-ca.pem

    # Identify admin and node identities from certificate DN
    plugins.security.authcz.admin_dn:
      - "CN=admin,O=AccTechCo,C=IR"

    plugins.security.nodes_dn:
      - "CN=opensearch-logs-master,O=AccTechCo,C=IR"

    plugins.security.allow_unsafe_democertificates: false
    plugins.security.allow_default_init_securityindex: true
```

> **Note:** `plugins.security.authcz.admin_dn` must exactly match the
> `subject` of `admin.pem`. Confirm before rollout with:
> ```bash
> openssl x509 -in ~/opensearch-certs/admin.pem -noout -subject
> ```
> and adjust the DN string/order in `override.yaml` if it differs.

## Step 4 — Deploy

```bash
git add override.yaml
git commit -m "opensearch: replace demo TLS certs with custom CA-signed certs"
git push origin dev
```

ArgoCD auto-syncs via `selfHeal: true`; to force immediately:

```bash
argocd app sync opensearch
```

Because the change affects volumes/volumeMounts (not just env vars), the
StatefulSet performs a rolling restart of all 3 pods.

## Step 5 — Verify

Confirm the new certificate is being served (not the demo one):

```bash
kubectl exec -it opensearch-logs-master-0 -n observability -c opensearch -- \
  openssl s_client -connect localhost:9200 -showcerts </dev/null 2>/dev/null | \
  openssl x509 -noout -subject -issuer
```

Expected:

```
subject=CN = opensearch-logs-master, O = AccTechCo, C = IR
issuer=CN = opensearch-root-ca, O = AccTechCo, C = IR
```

Confirm cluster health:

```bash
kubectl exec -it opensearch-logs-master-0 -n observability -c opensearch -- \
  curl -sk -u admin:<password> https://localhost:9200/_cluster/health?pretty
```

## Status

Certificates generated and Kubernetes Secret (`opensearch-certs`) created.
`override.yaml` change prepared, pending confirmation of `admin.pem` subject
before commit/deploy.

## Follow-up (not part of this TLS work)

Replace/remove the remaining default demo users (`kibanaserver`, `logstash`,
`readall`, etc.) — requires a custom `internal_users.yml` / `roles.yml` via
the chart's `securityConfig` override.
