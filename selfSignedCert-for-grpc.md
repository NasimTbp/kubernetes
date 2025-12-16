
### 🟢 SSL Certificate Configuration for gRPC Communication in Kubernetes

In several Kubernetes applications, inter-service communication relies on **gRPC**. When **Istio** is enabled in the cluster, mutual TLS (mTLS) encryption is automatically handled by Istio, which removes the need for any manual configuration. However, in environments **without Istio**, the DevOps team manually generates and installs SSL certificates to secure communication between gRPC-based services.

---

#### Certificate Generation Process

1. **Creating the Root Certificate Authority (CA)**
   A local Root CA is generated to sign all service-specific certificates.
   The following commands create the root key and certificate:

   ```
   openssl genrsa -out rootCA.key 4096
   openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 1825 -out rootCA.crt \
     -subj "/CN=MyK8sRootCA"
   ```

2. **Generating the Service Key and CSR**
   Each gRPC service that needs to be secured must have its own private key and certificate signing request (CSR).
   For example:

   ```
   openssl genrsa -out pv.key 2048
   openssl req -new -key pv.key -out pv.csr \
     -subj "/CN=grpc-kestrel-app.default.svc.cluster.local"
   ```

   ✅📍 It is important that the Common Name (CN) exactly matches the Kubernetes internal DNS name of the service.

3. **Signing the CSR Using the Root CA**
   The CSR is signed with the previously created Root CA, producing the service certificate:

   ```
   openssl x509 -req -in pv.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial \
     -out cert.pem -days 3650 -sha256
   ```

4. **Building the Full Certificate Chain**
   The service certificate and the root certificate are concatenated into a single file:

   ```
   cat cert.pem rootCA.crt > fullchain.pem
   ```

📍 This ensures that clients can validate the complete certificate chain when connecting to the service.

---

#### 🟢 Aligning with the Application Configuration

The development team’s code expects specific certificate file names. To maintain compatibility, we rename the generated files as follows:

* `fullchain.pem` is renamed to `cert.pem`
* `pv.key` is renamed to `privatekey.pem`

These names correspond to the file paths referenced in the gRPC service code, so keeping them consistent avoids any runtime errors or configuration mismatches.

---

#### Mounting Certificates in Kubernetes Pods

1. **gRPC Server Application**
   For applications where gRPC and WMS are enabled, the certificate files are mounted inside the container under the path `/app/cert`.
   This is achieved using a **PersistentVolume (PV)** and **PersistentVolumeClaim (PVC)** that contain the `cert.pem` file (originally `fullchain.pem`).
   This allows the gRPC server to load its TLS credentials directly from the mounted volume.

sample:
```
      volumes:
        - name: ssl-cert-volume
          persistentVolumeClaim:
            claimName: hamyar-esales-hotfix
```
```
          volumeMounts:
            - name: ssl-cert-volume
              mountPath: /app/cert
```
2. **gRPC Client Application**
   For applications that need to connect to the gRPC server, the certificate chain file (`cert.pem`, which corresponds to `fullchain.pem`) is provided via a **ConfigMap**.
   Mounting the file through a ConfigMap allows the client to verify the server’s certificate during the TLS handshake without needing a persistent volume.
   ```
      volumes:
        - name: cert-volume
          configMap:
            name: hamyar-gateway-to-esales-panel-cert
            defaultMode: 420
   ```
   ```
             volumeMounts:
            - name: cert-volume
              readOnly: true
              mountPath: /etc/ssl/certs/cert.pem
              subPath: cert.pem
   ```
---

#### 🎯 Summary

In summary:

* When Istio is not available, SSL certificates are manually generated to secure gRPC traffic.
* Each gRPC service uses a certificate signed by a locally generated Root CA.
* File names are standardized (`cert.pem` and `privatekey.pem`) to match the application’s internal configuration.
* gRPC servers mount certificates via PersistentVolumes, while clients use ConfigMaps for certificate validation.

This configuration ensures encrypted and authenticated communication between gRPC-based microservices in Kubernetes clusters without Istio, maintaining both security and compatibility with the existing deployment structure.

---


# 🟢 Method 2 

### IF the above method doesn't worrk properly

# GRPC Self-Signed Certs are here
cert.pem
privatekey.pem

these files are used insid the directory /mnt/nfs-data/hamyar-esales-admin-panel/app/cert in nfs and used inside the 
config map in Kestrel section


1️⃣ Create a working directory
mkdir ~/ssl-gen && cd ~/ssl-gen

2️⃣ Create your Root CA (used to sign all internal certs)

- Generate private key for your CA
```
openssl genrsa -out ca.key 4096
```

- Create the CA certificate (valid 10 years)
```
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.crt \
-subj "/C=US/ST=Example/L=Example/O=MyOrg/OU=DevOps/CN=internal-root-ca"
```

- You now have:
```
🔹 ca.key  → private key (keep secret)
🔹 ca.crt  → root CA certificate (distribute to trust stores)
```

3️⃣ Create a private key for your service
```
openssl genrsa -out privatekey.pem 2048
```

4️⃣ Create a CSR (Certificate Signing Request)
Create a file named san.cnf (this defines the Subject and SANs):
```declarative
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = Example
L = Example
O = MyOrg
OU = DevOps
CN = hamyar-esales-svc.hamyar-esales.svc.cluster.local

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = hamyar-esales-svc.hamyar-esales.svc.cluster.local
```
- Now run:
```
openssl req -new -key privatekey.pem -out cert.csr -config san.cnf
```

5️⃣ Sign the CSR with your CA
```
openssl x509 -req -in cert.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
-out cert.pem -days 3650 -sha256 -extfile san.cnf -extensions v3_req
```

- Now you have:

```
ca.key          → Root CA private key
ca.crt          → Root CA certificate
privatekey.pem  → Service private key
cert.pem        → Service certificate signed by your CA
cert.csr        → CSR (you can delete after signing)
```

6️⃣ Verify the generated certificate
```
openssl x509 -in cert.pem -noout -subject -issuer -ext subjectAltName
openssl verify -CAfile ca.crt cert.pem
```


- Expected output:

```
subject=CN = org-app-svc.org-app.svc.cluster.local
issuer=CN = internal-root-ca
X509v3 Subject Alternative Name:
DNS:esales-panel-svc, DNS:org-app-svc.org-app.svc, DNS:org-app-svc.org-app.svc.cluster.local
cert.pem: OK
```

7️⃣ Transfer certs to a single .pfx file for better use in Kestrel

```
openssl pkcs12 -export -out cert-with-chain.pfx -inkey privatekey.pem -in cert.pem -certfile ca.crt -passout pass:123NotImportantPassword
```

8️⃣ Move this files to your app storage ( ex: nfs , ...)

      ca.crt  
      cert.pem  
      cert-with-chain.pfx  
      privatekey.pem
