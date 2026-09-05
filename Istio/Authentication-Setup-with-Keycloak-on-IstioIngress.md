# Jaeger SSO Authentication Setup Report with Keycloak on Istio

**Project Goal:** Restrict access to `jaeger-energy-test.mycompany.com` to authenticated users through Keycloak (SSO), without changing any of the other hosts currently configured on the Istio Gateway.

---

## 🟢 1. Final Architecture

```text
Browser
    │
    ▼
Istio Public Gateway (istio-ingress)
    │  (VirtualService: jaeger-energy-group-vs)
    ▼
oauth2-proxy (new pod in observability-energy-group)
    │
    ├──► Browser is redirected to Keycloak for login
    │    (public login-url: keycloak-test.mycompany.com)
    │
    ├──► After login, oauth2-proxy connects directly to Keycloak
    │    through the internal Service to validate and obtain the token
    │    (internal redeem-url / jwks-url / profile-url)
    │
    ▼
jaeger-energy-group (main Jaeger service, port 16686)
```

**Key architectural point:** Jaeger itself was not modified and is unaware of the authentication layer. All SSO logic is implemented in an intermediary pod (`oauth2-proxy`) placed in front of Jaeger.

---

## 🟢 2. Steps Performed in Order

### 2.1 Setting Up the Infrastructure in Keycloak

1. **Created a new Realm:** `istio-authentication`

    * This separate Realm was created instead of using `master`, so users of internal tools (such as Jaeger) are separated from users of other systems.

2. **Created a Client in this Realm:**

    * Client ID: `jaeger-energy-oauth2-proxy`
    * Client authentication: On (Confidential client)
    * Standard flow: Enabled
    * Valid redirect URIs: https://jaeger-energy-test.mycompany.com/oauth2/callback
    * Valid post logout redirect URIs: https://jaeger-energy-test.mycompany.com/*
    * Web origins: https://jaeger-energy-test.mycompany.com
    * The Client Secret was obtained from the Credentials tab.

3. **Created a test user:** `jaeger-test`

    * Initially created without an email address, which later caused an error (see Section 3).
    * Eventually, the email `jaeger-energy-test@mycompany.com` was added to the user and verified.

### 2.2 Creating the Secret in Kubernetes

A Secret was created to securely store the connection information:

```bash
COOKIE_SECRET=$(python3 -c 'import secrets,base64; print(base64.b64encode(secrets.token_bytes(16)).decode())') echo "Cookie secret: $COOKIE_SECRET"

kubectl create secret generic oauth2-proxy-jaeger-energy \
  --namespace=observability-energy-group \
  --from-literal=client-id=jaeger-energy-oauth2-proxy \
  --from-literal=client-secret='<from Keycloak>' \
  --from-literal=cookie-secret='<generated using secrets.token_bytes>'
```

* `client-id` / `client-secret`: The identity of oauth2-proxy when communicating with Keycloak.
* `cookie-secret`: The encryption key for the user's session cookie in the browser (randomly generated and independent of Keycloak).

### 2.3 Deploying oauth2-proxy

A new Deployment and Service were created in the `observability-energy-group` namespace (the same namespace as Jaeger):

* **image:** `oauth2-proxy` — because the internal registry (`repo.mycompany.com:8xxx`) did not have Internet access, the image was manually pulled from another server → tagged → pushed.
* **Service:** `oauth2-proxy-jaeger` on port `4180`.

### 2.4 Redirecting Traffic (VirtualService)

The `destination` in the existing VirtualService (`jaeger-energy-group-vs`) was changed from the direct Jaeger service to the new oauth2-proxy service:

```yaml
route:
  - destination:
      host: oauth2-proxy-jaeger.observability-energy-group.svc.cluster.local
      port:
        number: 4180
```

---

## 🟢 3. Problems Encountered and the Solution for Each

During the implementation, we encountered the following errors in order — each one represented a different layer of the system:

| # | Error                                                         | Root Cause                                                                                                                                                                                             | Solution                                                                                                                                                                                   |
| - | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1 | `connection reset by peer` during OIDC Discovery              | The namespace was inside the Istio mesh with `outboundTrafficPolicy: REGISTRY_ONLY`; the request to the public Ingress IP (Hairpin) was rejected by the Envoy sidecar                                  | Use `--skip-oidc-discovery=true` + manual endpoint configuration: public `login-url` (for the browser) and `redeem-url`/`jwks-url`/`profile-url` directly to the internal Keycloak Service |
| 2 | `Invalid username or password`                                | Testing was performed through the Admin Console, which always authenticates against the `master` Realm, not the Realm selected in the dropdown                                                         | Test through the actual application path (`jaeger-energy-test.mycompany.com`), which correctly called the `istio-authentication` Realm                                                     |
| 3 | `Update Account Information` (mandatory form)                 | Keycloak's default Required Action for completing `First name`/`Last name`                                                                                                                             | Complete the form manually                                                                                                                                                                 |
| 4 | `email in id_token () isn't verified`                         | The `jaeger-test` user's email did not exist / was not verified                                                                                                                                        | Add `--insecure-oidc-allow-unverified-email=true`                                                                                                                                          |
| 5 | `neither the id_token nor the profileURL set an email`        | The user did not have an email address at all (not merely an unverified email)                                                                                                                         | Add a real email address to the user in Keycloak and verify it                                                                                                                             |
| 6 | `HTTP 502` (very quickly, without any network attempt)        | oauth2-proxy was preserving the browser's `Host` header (the public domain); the Envoy sidecar in the oauth2-proxy pod did not recognize this Host for the internal Service and could not find a route | Add `--pass-host-header=false` so that the Host is replaced with the internal upstream address                                                                                             |
| 7 | After login, the user was never logged out (infinite session) | No time limit had been configured for the oauth2-proxy session cookie                                                                                                                                  | Add `--cookie-expire=24h` (maximum session lifetime) and `--cookie-refresh=1h` (automatic token refresh during the session)                                                                |

---

## 🟢 4. Final Deployment Configuration

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oauth2-proxy-jaeger
  namespace: observability-energy-group
spec:
  replicas: 1
  selector:
    matchLabels:
      app: oauth2-proxy-jaeger
  template:
    metadata:
      labels:
        app: oauth2-proxy-jaeger
    spec:
      containers:
        - name: oauth2-proxy
          image: repo.mycompany.com:8xxx/oauth2-proxy/oauth2-proxy:latest
          args:
            - --provider=keycloak-oidc
            - --client-id=$(CLIENT_ID)
            - --client-secret=$(CLIENT_SECRET)
            - --cookie-secret=$(COOKIE_SECRET)
            - --email-domain=*
            - --upstream=http://jaeger-energy-group.observability-energy-group.svc.cluster.local:16686
            - --http-address=0.0.0.0:4180
            - --redirect-url=https://jaeger-energy-test.mycompany.com/oauth2/callback
            - --cookie-secure=true
            - --skip-provider-button=true
            - --skip-oidc-discovery=true
            - --oidc-issuer-url=https://keycloak-test.mycompany.com/realms/istio-authentication
            - --login-url=https://keycloak-test.mycompany.com/realms/istio-authentication/protocol/openid-connect/auth
            - --redeem-url=http://keycloak.keycloak-test.svc.cluster.local:80/realms/istio-authentication/protocol/openid-connect/token
            - --oidc-jwks-url=http://keycloak.keycloak-test.svc.cluster.local:80/realms/istio-authentication/protocol/openid-connect/certs
            - --profile-url=http://keycloak.keycloak-test.svc.cluster.local:80/realms/istio-authentication/protocol/openid-connect/userinfo
            - --insecure-oidc-allow-unverified-email=true
            - --pass-host-header=false
            - --cookie-expire=24h
            - --cookie-refresh=1h
          env:
            - name: CLIENT_ID
              valueFrom:
                secretKeyRef: {name: oauth2-proxy-jaeger-energy, key: client-id}
            - name: CLIENT_SECRET
              valueFrom:
                secretKeyRef: {name: oauth2-proxy-jaeger-energy, key: client-secret}
            - name: COOKIE_SECRET
              valueFrom:
                secretKeyRef: {name: oauth2-proxy-jaeger-energy, key: cookie-secret}
          ports:
            - containerPort: 4180
          readinessProbe:
            httpGet: {path: /ping, port: 4180}
            initialDelaySeconds: 5
          livenessProbe:
            httpGet: {path: /ping, port: 4180}
            initialDelaySeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: oauth2-proxy-jaeger
  namespace: observability-energy-group
spec:
  selector:
    app: oauth2-proxy-jaeger
  ports:
    - port: 4180
      targetPort: 4180
```

### Final VirtualService

```yaml
kind: VirtualService
apiVersion: networking.istio.io/v1
metadata:
  name: jaeger-energy-group-vs
  namespace: observability-energy-group
spec:
  hosts:
    - jaeger-energy-test.mycompany.com
  gateways:
    - istio-ingress/istio-public-gateway
  http:
    - name: "jaeger-energy-root"
      match:
        - uri:
            prefix: /
      route:
        - destination:
            host: oauth2-proxy-jaeger.observability-energy-group.svc.cluster.local
            port:
              number: 4180
```

---

## 🟢 5. Important Notes for the Future

### Why Did We Use `--skip-oidc-discovery`?

Because Keycloak is accessible from inside the cluster (Envoy/Istio mesh) and from outside (browser) through two different paths. The external path (Ingress) was unknown to the mesh and caused the connection to be reset; therefore, the server-to-server endpoints were explicitly directed to the internal Service, while only the browser path (`login-url`) remained public.

### Why Was `--pass-host-header=false` Required?

Because Istio (Envoy sidecar) performs HTTP routing based on the `Host` header. If this header contains a domain outside the mesh (such as `jaeger-energy-test.mycompany.com`), Envoy cannot find a valid route and immediately returns a 502.

### Session Expiry Management

After the initial deployment, it became clear that the user was never automatically logged out (the session remained open indefinitely). To limit the session lifetime to 24 hours, two flags were added to oauth2-proxy:

| Flag                  | Role                                                                                                                                                                                                                           |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `--cookie-expire=24h` | Absolute maximum lifetime of the session cookie; exactly 24 hours after login, the cookie becomes completely invalid and the user must log in again — regardless of how active the user has been                               |
| `--cookie-refresh=1h` | Every 1 hour, oauth2-proxy automatically and in the background (using the `refresh_token`) obtains a fresh access token from Keycloak, so the user does not encounter an "expired token" error during the same 24-hour session |

**Important coordination note:** These two flags only control the local browser cookie. If we want the expiration to actually require the user to enter their username/password again (rather than being automatically logged in because an active SSO session still exists in Keycloak), the following values in the Keycloak Realm settings (`istio-authentication` → Sessions/Tokens tab) should also be aligned with the same timeframe:

* **SSO Session Max**: Maximum 24 hours (or less)
* **SSO Session Idle**: Depending on the project's requirements

**Test performed:** To verify correct behavior, `--cookie-expire` was temporarily set to `5m` (and `--cookie-refresh=0`) and automatic logout after 5 minutes was confirmed. The final values were then restored to `24h` / `1h`.

### About New Users

Every new user created in the `istio-authentication` Realm must:

1. Have a valid **Email** address (even if it is not verified, because the unverified flag is enabled).
2. If required, complete the `First name`/`Last name` fields during the first login (Keycloak's default Required Action).

### Restricting Access to a Specific Group (Optional, Not Yet Implemented)

In the future, if you want only members of a specific group (for example, the DevOps team) to have access to Jaeger:

1. Create a Group in Keycloak and add the authorized users to it.
2. Add a Group Membership Mapper to the Client so that the `groups` claim is included in the token.
3. Add the following arguments to the Deployment:

```yaml
- --allowed-group=/<group-name>
- --oidc-groups-claim=groups
```

---

## 🟢 6. Final Result Summary

Currently, accessing `https://jaeger-energy-test.mycompany.com` redirects the user to the Keycloak login page (Realm `istio-authentication`) before displaying the Jaeger dashboard, and access to Jaeger data is granted only after successful authentication — without making any changes to the other ~60 hosts configured on the same Istio Gateway.

In addition, the user's session automatically expires after **24 hours** and requires the user to log in again.
