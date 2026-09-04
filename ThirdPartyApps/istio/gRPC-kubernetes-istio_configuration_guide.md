### Report: Handling gRPC Communication in Kubernetes with Istio

This report outlines the necessary steps for setting up and handling gRPC communication in a Kubernetes environment with Istio. The steps include configuring the destination service ports, adding Kestrel configurations, removing environment variables, and modifying destination paths for gRPC.

---

#### **Step 1: Modify Destination Service Ports**

To ensure that the destination service functions correctly and can handle both gRPC and HTTP requests, you need to modify the service port configuration. This ensures that the **destination** service listens on different ports for gRPC and HTTP traffic.

```yaml
spec:
  ports:
    - name: grpc
      protocol: TCP
      port: 8080
      targetPort: 8080
    - name: httpapi
      protocol: TCP
      port: 8081
      targetPort: 8081
```

* **Port 8080** for gRPC (using HTTP/2).
* **Port 8081** for HTTP API (using HTTP/1.1).

This configuration ensures that the destination service can handle both gRPC and HTTP requests appropriately.

---

#### **Step 2: Add Kestrel Configuration to the Destination ConfigMap**

To ensure that the destination service is correctly configured with Kestrel for both gRPC and HTTP, you need to add a ConfigMap that includes the necessary Kestrel settings. In this section, the URLs and protocols for gRPC and HTTP are specified for the **destination** service.

```json
"Kestrel": {
  "Endpoints": {
    "Grpc": {
      "Url": "http://0.0.0.0:8080",
      "Protocols": "Http2"
    },
    "HttpApi": {
      "Url": "http://0.0.0.0:8081",
      "Protocols": "Http1"
    }
  },
  "IsEnabled": "false"
}
```

* Two endpoints are defined: one for **gRPC** (on port 8080) and one for **HTTP API** (on port 8081).
* The `IsEnabled: false` setting is included to disable default configurations that might conflict with the custom settings for Kestrel.

---

#### **Step 3: Remove Environment Variables in the Destination**

Next, you need to remove any environment variables in the **destination** that may cause conflicts, such as those that define the environment type (e.g., Staging or Production). These variables are often set by default but can interfere with specific configuration settings.

```yaml
env:
  - name: ASPNETCORE_ENVIRONMENT
    value: Staging
```

By removing this block, you avoid potential conflicts between the default environment settings and the specific configuration required for the destination service to work as intended.

---

#### **Step 4: Modify Destination Paths in the Source**

Finally, the **source** service paths need to be updated to correctly route gRPC requests to the destination services. These paths should be updated using the internal Kubernetes DNS names, as shown below:

```json
"ESalesGRpc": "http://hamyar-esales-svc.hamyar-esales.svc.cluster.local:8080",
"IdpGRpc": "http://identity-server-svc.identity-server.svc.cluster.local:8080"
```

* The paths for gRPC are now specified with internal DNS names within the Kubernetes cluster, ensuring that requests are directed to the correct destination services (`hamyar-esales` and `identity-server`).
* This setup ensures that gRPC requests are routed properly without any DNS resolution issues.

---

### **Conclusion:**

By following these steps, gRPC communication within Kubernetes using Istio will be correctly configured. The services will be able to handle both gRPC and HTTP traffic, ensuring proper routing and communication. These configurations are designed to optimize performance and prevent common issues associated with handling gRPC and HTTP requests in a Kubernetes environment with Istio.
