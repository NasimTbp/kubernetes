# Technical Report on Mongo-Express in Kubernetes (Detailed Configuration)

## 🎯 1. Introduction

**Mongo-Express** is a web-based interface for managing **MongoDB** databases. It allows viewing and editing data, managing collections and databases, and running queries via a browser. 
Mongo-Express itself **does not manage users or roles**; all access control is enforced by **MongoDB**.

---

## 🎯 2. Mongo-Express Architecture in Kubernetes

### 2.1 Deployment

Mongo-Express runs as a **Deployment**. Important environment variables from your configuration are:

| Variable                          | Value                                                                        | Description                                                  |
| --------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `ME_CONFIG_MONGODB_ADMINUSERNAME` | `root`                                                                       | MongoDB username used by Mongo-Express to connect to MongoDB |
| `ME_CONFIG_MONGODB_ADMINPASSWORD` | `HamyarEsales3rvice2025`                                                     | MongoDB password for the admin user                          |
| `ME_CONFIG_MONGODB_SERVER`        | `hamyar-esales-mongo-mongodb-headless.mongo-hamyar-esales.svc.cluster.local` | Address of the MongoDB server in Kubernetes                  |
| `ME_CONFIG_MONGODB_PORT`          | `27017`                                                                      | MongoDB port                                                 |
| `ME_CONFIG_MONGODB_AUTH_DATABASE` | `admin`                                                                      | Database used for authentication                             |
| `ME_CONFIG_OPTIONS_REPLICA_SET`   | `rs0`                                                                        | Optional: Specifies the replica set name for MongoDB         |
| `ME_CONFIG_OPTIONS_READONLY`      | `true`                                                                       | Optional: Makes the Mongo-Express interface read-only        |
| `ME_CONFIG_BASICAUTH_USERNAME`    | `user`                                                                       | Username for HTTP BasicAuth to access the Mongo-Express UI   |
| `ME_CONFIG_BASICAUTH_PASSWORD`    | `Esal3sS3rvice2025!$)$`                                                      | Password for HTTP BasicAuth                                  |

> These are all the environment variables defined in our Deployment file.
> Additional optional configuration variables and advanced settings can be found at: 🔗 \[https://github.com/mongo-express/mongo-express?tab=readme-ov-file].

---

### 2.2 Service

* Mongo-Express is exposed via a **Service** of type `ClusterIP` to allow Pods to communicate and for the Ingress to access the UI.
* Port configuration:

  ```yaml
  ports:
    - port: 8081
      targetPort: 8081
  ```

---

## 🎯 3. User Management and Access Control

### 3.1 MongoDB Authentication

* Mongo-Express connects to MongoDB using credentials defined in `ME_CONFIG_MONGODB_ADMINUSERNAME` and `ME_CONFIG_MONGODB_ADMINPASSWORD`.
* The user's access level depends on **roles in MongoDB**, e.g., `read` or `readWrite`.

### 3.2 HTTP BasicAuth

* Controlled via `ME_CONFIG_BASICAUTH_USERNAME` and `ME_CONFIG_BASICAUTH_PASSWORD`.
* This login is **only for accessing the UI**, independent of MongoDB credentials.

### 3.3 Multiple Users

* By default, Mongo-Express only uses the credentials in environment variables to connect.
* To allow multiple users with their own credentials, you need **OIDC (OpenID Connect)** integration with an Identity Provider (e.g., Keycloak, Auth0).
* For testing purposes, you can create multiple users in MongoDB, but only the Deployment credentials will be used unless OIDC is configured.

---

## 🎯 4. Summary

* Mongo-Express is a web management tool; users and roles are managed by **MongoDB**.
* Access to MongoDB is controlled by the credentials defined in environment variables.
* **BasicAuth** is for UI security; **MongoDB roles** are for database access.
* For multiple users with distinct credentials, OIDC or multiple Deployments are required.
* The deployment structure involves **Deployment → Service → Ingress**, which ensures proper routing and security.

> All configuration variables defined in your Deployment are included above.
> For additional advanced variables and full configuration options, you can refer to 🔗 \[https://github.com/mongo-express/mongo-express?tab=readme-ov-file].

---
