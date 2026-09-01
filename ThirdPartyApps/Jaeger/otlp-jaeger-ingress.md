# 🎯 OTLP Traces Through an Ingress (Jaeger + Kubernetes)

We run Jaeger inside a Kubernetes cluster (in an Istio mesh), exposed internally via a ClusterIP service with two relevant ports:

- `4317` — OTLP over gRPC
- `4318` — OTLP over HTTP/protobuf

One internal service, already running inside the cluster, sends traces directly to the collector's internal DNS name over gRPC on port `4317`. That path never went through an Ingress and always worked fine.

A second application — running outside the cluster, on its own server — needed to send traces to the same Jaeger collector through a public-facing Ingress (`nginx-ingress`, with TLS termination).

---

## 🟢 Symptom

Traces from the external app never showed up in Jaeger.

The app's OpenTelemetry exporter logged:

```text
HTTP request to https://<jaeger-ingress-host>/ failed.
Response status code does not indicate success: 404 (Not Found).
````

---

## 🟢 The investigation (short version)

This took a while to pin down because there were actually two separate, unrelated services talking to Jaeger, and early tests kept mixing signals from both:

First we assumed the problem was TLS / self-signed certs — it wasn't; the Ingress had a real, valid certificate.

Then we assumed it was a gRPC vs HTTP/2 framing issue at the Ingress — this was a real issue, but for the other (internal) service, which uses port `4317` (gRPC) directly and never even goes through the Ingress.

Testing gRPC through the Ingress with `curl`/`wget` is a dead end anyway: those tools can't speak gRPC, so getting `415`, `502`, or garbled output from them doesn't tell you anything concrete about whether the backend is healthy — a plain gRPC-aware client (`grpcurl`) is needed to get a meaningful answer.

Once we correctly identified *which* app was actually failing (the external, HTTP-based one, not the internal gRPC one), and tested the exact same URL from the exact same external server the app runs on, we consistently got a clean `200 OK` — but only when hitting `/v1/traces`, not the bare host root `/`.

That was the key clue: the app's exporter was sending requests to the bare host root instead of `/v1/traces`.

---

## 🟢 Root cause

OTLP's HTTP/protobuf exporter is supposed to automatically append `/v1/traces` (or `/v1/metrics`, `/v1/logs`) to whatever base endpoint URL you configure — but depending on the SDK/package version, that auto-append behavior isn't always present.

In this case, the configured endpoint was just the bare host (`https://<host>`), the SDK wasn't appending the path, and the collector (correctly) returned 404 for any request to `/`.

---

## 🟢 Fix

Two options, we went with the first for speed:

### Add the path explicitly in config

**Simplest, no code change:**

```json
"OtlpEndpoint": "https://<jaeger-ingress-host>/v1/traces"
```

### Upgrade the OTLP exporter package

Upgrade the OTLP exporter package to a version where the SDK correctly auto-appends the signal-specific path, and keep the endpoint as just the bare host.

📍 After adding `/v1/traces` explicitly, traces started showing up in Jaeger immediately.

---

## 🟢 Reference: picking the right port/protocol for Ingress

| Port   | Protocol      | When to use                                                                                                                                                                                                                                                                                                                                  |
| ------ | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `4317` | gRPC (HTTP/2) | **Service-to-service traffic inside** the cluster, hitting the collector directly via its internal DNS name — no Ingress involved. Works well, but exposing gRPC cleanly through an HTTP-oriented ingress controller adds real complexity (protocol detection, buffering, `backend-protocol: GRPC` annotations, client ALPN behavior, etc.). |
| `4318` | HTTP/protobuf | Anything coming from **outside** the cluster, or from any client that doesn't want to deal with gRPC. Trivial to test with plain `curl`, and plays nicely with a standard HTTP-mode Ingress.                                                                                                                                                 |

### Example Ingress for the HTTP/4318 path

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: otel-collector-ing
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - <your-otel-ingress-host>
      secretName: <your-tls-secret>
  rules:
    - host: <your-otel-ingress-host>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <collector-service-name>
                port:
                  number: 4318
```

If you're exposing gRPC (`4317`) through the same kind of Ingress instead, you'd need `backend-protocol: "GRPC"` plus (in our experience) explicitly disabling request/response buffering on the Ingress — and even then, routing gRPC through a non-mesh-aware HTTP proxy in front of a mesh-aware sidecar is inherently more fragile than just using HTTP for anything crossing that boundary.

---

## 🎯 Lessons learned

* **Don't test gRPC endpoints with `curl`/`wget`.** They can't speak the protocol properly and any error you get back (`415`, `502`, garbled `HTTP/0.9`) is more about the tool than the server. Use `grpcurl`.

* **A `200 OK` from a manual `curl` test doesn't guarantee the app's real client is sending the same request.** The actual bug here was entirely in what URL the app's SDK constructed — not the network, not the Ingress, not TLS. We only found it once we got a genuine log line out of the OpenTelemetry SDK's own diagnostics showing the exact URL and status code it received.

* **Enable SDK/exporter diagnostics early.** A lot of time was spent testing infrastructure that turned out to be fine. If we'd captured the exporter's internal diagnostic log first, we'd have seen `404 https://.../` immediately and skipped most of the intermediate steps.

* **When there are multiple services with similar names/config talking to the same backend, make sure you know which one you're actually debugging** — several early dead ends came from testing/assuming behavior for one service while the actual failure was in a different one.

```
```
