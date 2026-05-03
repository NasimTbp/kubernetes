### 🎯 Introduction to Ambient Mode in Istio

Ambient Mode is the next-generation service mesh architecture in Istio, designed to simplify deployment, reduce resource consumption, and eliminate the need for sidecar injection in every Pod.

In the traditional Istio architecture, each Pod requires a sidecar proxy (Envoy), which increases CPU and memory usage and adds operational complexity. In contrast, Ambient Mode separates the data plane into two layers:

1. **ztunnel**, running at the node level, which handles Layer 4 responsibilities such as mTLS encryption, basic authentication, and secure connectivity.
2. **Waypoint Proxy**, which is optional and used when Layer 7 processing is required (e.g., advanced AuthorizationPolicy, HTTP routing, header-based rules).

In this architecture, no sidecar is injected into application Pods. Service-to-service communication is tunneled using the HBONE protocol over port 15008. This significantly reduces overhead and simplifies operations compared to the sidecar model.

---

## 🎯 Required Changes to Enable Ambient

### 🧩 1. Adding the Ambient Label to the Namespace

The first step to enable Ambient in a namespace is adding the appropriate dataplane label. This tells Istio that workloads in this namespace should participate in Ambient Mode:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: redis-customerclub
  labels:
    istio.io/dataplane-mode: ambient
```

This label ensures that traffic from Pods in this namespace is captured by ztunnel and automatically secured using mTLS.

---

### 🧩 2. Adjusting AuthorizationPolicy for Ambient

If an AuthorizationPolicy already exists in the namespace, it must be reviewed carefully when migrating to Ambient Mode.

In the sidecar model, policies were enforced directly on each Pod’s Envoy proxy. In Ambient:

* Layer 4 policies are enforced by ztunnel.
* Layer 7 policies (HTTP-based rules, JWT validation, header matching, etc.) require a Waypoint proxy.

Therefore, if the namespace uses HTTP-based AuthorizationPolicy rules, a Waypoint must be deployed. Otherwise, policies must be simplified to L4-level rules. Failing to do so may result in policies not being applied as expected.

---

### 🧩 3. Managing NetworkPolicy and Helm Overrides (Redis & RabbitMQ)

For stateful services such as Redis and RabbitMQ, enabling Ambient requires more than just labeling the namespace. Helm chart overrides and NetworkPolicy configurations must be adjusted.

Ambient uses port **15008** (HBONE) for internal mesh communication. If this port is not allowed in NetworkPolicy, traffic will be blocked.

📍 Example for **RabbitMQ**:

```yaml
networkPolicy:
  enabled: true
  extraIngress:
    - ports:
        - port: 15008   # istio ambient (HBONE)
        - port: 4369    # epmd
        - port: 25672   # inter-node
        - port: 5672    # amqp
        - port: 15672   # management
        - port: 15692   # prometheus metrics
```

📍 Example for **Redis**:

```yaml
networkPolicy:
  extraIngress:
    - ports:
        - port: 15008
```

For each application, the required overrides must be aligned with the official Helm chart configuration. Otherwise, service connectivity (for example, application-to-Redis or intra-cluster RabbitMQ communication) may fail due to blocked traffic or misinterpreted connection errors.

---

### 🧩 4. Defining HTTPRoute for Frontend Applications

In Ambient Mode, it is recommended to use the Gateway API instead of the traditional VirtualService resource.

For frontend services exposed through a public gateway, an HTTPRoute must be defined:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hamyar-app-route
  namespace: hamyar-app
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      namespace: pubgw-ing
      name: public-gateway
  hostnames:
    - activewarranty.acctechco.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - group: ''
          kind: Service
          name: hamyar-app-svc
          port: 80
          weight: 1
```

In this structure, the Gateway acts as the entry point, and HTTPRoute defines how traffic is routed to the backend service.

---

### 🧩 5. Deploying a Waypoint for Namespaces Requiring L7 Processing

Some applications require Layer 7 processing, such as:

* HTTP-based AuthorizationPolicy rules
* Header-based routing
* JWT validation
* Rate limiting
* Internal API gateways

In these cases, in addition to enabling Ambient, a Waypoint must be defined for the namespace.

📍 First, add the Waypoint label to the namespace:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: hamyar-gateway
  labels:
    istio.io/dataplane-mode: ambient
    istio.io/use-waypoint: hamyar-gateway-waypoint
```

📍 Then create the Waypoint Gateway object:

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: hamyar-gateway-waypoint
  namespace: hamyar-gateway
  labels:
    istio.io/waypoint-for: all
spec:
  gatewayClassName: istio-waypoint
  listeners:
    - name: mesh
      port: 15008
      protocol: HBONE
```

The Waypoint acts as a shared Envoy proxy for the namespace and enforces Layer 7 policies and advanced routing logic.

---

🎯 ## Conclusion

Enabling Ambient Mode in Kubernetes involves several coordinated steps. First, namespaces must be labeled to participate in Ambient. Second, AuthorizationPolicy definitions must be reviewed and adjusted based on whether L4 or L7 enforcement is required. Third, stateful services such as Redis and RabbitMQ require NetworkPolicy and Helm overrides to allow HBONE traffic on port 15008. Frontend services should be exposed using Gateway API and HTTPRoute. Finally, any namespace requiring Layer 7 policy enforcement must define and use a Waypoint proxy.

Compared to the sidecar model, Ambient Mode provides a lighter, more scalable, and operationally simpler architecture. However, it requires careful configuration of NetworkPolicy, Gateway API resources, and security policies to ensure correct and secure service communication.
