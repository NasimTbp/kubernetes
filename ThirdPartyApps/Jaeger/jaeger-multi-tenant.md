
# Technical Report: Setting Up Parallel Jaeger Instances for Team-Level Access Isolation

**Date:** August 15, 2026  
**Environment:** Kubernetes cluster with Istio Service Mesh  
**Subject:** Simultaneously routing distributed traces to two separate Jaeger instances

---

## 🟢 1. Goal

The goal was to provide distributed tracing access to developers on different teams, without giving each team access to trace data for the entire cluster.

A central Jaeger instance existed in the `observability` namespace, receiving all mesh traffic, used by the admin/infrastructure team.

A separate Jaeger instance was needed for the Energy team, deployed in the `observability-energy-group` namespace, that would see only traffic belonging to that team's applications (e.g. `energy-app`) — without exposing traffic from the rest of the cluster's applications to that team's developers.

Ultimately, some applications needed to send their traces simultaneously to both the central Jaeger and their team's dedicated Jaeger.

---

## 🟢 2. Core Constraint and Architectural Solution

Istio's Telemetry CRD allows configuring an "Extension Provider" for sending traces. However, Envoy only supports a single tracing provider per route — when multiple providers are listed together under one Telemetry entry, Envoy only applies the first one and silently ignores the rest.

To work around this limitation, an intermediary OpenTelemetry Collector (`otel-energy-router`) was deployed in the `observability-energy-group` namespace, which:

- Was registered as the sole Extension Provider for the `energy-app` namespace (via a separate, namespace-scoped Telemetry resource).
- Internally fans out every received span to two destinations simultaneously:
  - the central Jaeger (`jaeger.observability`)
  - the Energy team's dedicated Jaeger (`jaeger-energy.observability-energy-group`).

This pattern (using an OTel Collector as an intermediate router) is a well-known and common solution for working around Envoy's single-provider limitation.

---

## 🟢 3. Troubleshooting Path

The rollout went through several stages, each surfacing a distinct issue that was resolved in turn:

### 3.1. Initial Jaeger migration from raw manifests to Helm

The previous Jaeger deployment used a raw manifest (with local badger storage) in the `istio-system` namespace.

The new version (Helm chart, OpenSearch-backed storage) was deployed to the `observability` namespace.

The first issue was that both the old and new providers were listed together in a single Telemetry resource, and Envoy only ever applied the old provider — so no data reached the new instance.

**Temporary test fix:** creating a separate, namespace-scoped Telemetry (limited to a single test namespace) that referenced only the new provider, without touching the existing cluster-wide configuration.

---

### 3.2. Deploying the intermediary OTel Collector (`otel-energy-router`)

After confirming the new pipeline was healthy, an OTel Collector with two exporters (`otlp_grpc/jaeger-admin` and `otlp_grpc/jaeger-energy`) was deployed to send traces to both Jaeger instances at once.

However, after deployment, no data was reaching either Jaeger.

Step-by-step investigation (Collector logs, exporter metrics, Envoy sidecar `config_dump`, checking for a possible mTLS conflict via `PeerAuthentication`) showed that the infrastructure itself (provider config, network connectivity, absence of enforced mTLS) was healthy.

The real cause was a low sampling rate (10%) set on the mesh-wide Telemetry resource — most test requests simply weren't being sampled, so no spans were generated in the first place.

After temporarily raising `randomSamplingPercentage` to 100% for testing, part of the pipeline (delivery to the central Jaeger) was confirmed working.

---

### 3.3. Final issue: service port naming

Even with a healthy provider, network connectivity, and sampling confirmed, data still wasn't reaching the Energy team's dedicated Jaeger.

A closer look at Envoy's stats (`/clusters` and `/stats` on the admin port, `15000`) revealed:

- The TCP connection to `otel-energy-router` was being established successfully (`cx_connect_fail: 0`).
- But every single request was failing (`rq_error: 23`, `rq_success: 0`).

#### ⚠️ Root cause

The Kubernetes Service port for `otel-energy-router` was named `otlp-grpc`.

Istio relies on service port name prefixes to automatically detect the wire protocol (HTTP/2, gRPC, or raw TCP); recognized prefixes include `grpc-`, `http-`, `http2-`, and similar.

The name `otlp-grpc` started with the prefix `otlp`, which Istio does not recognize — so Envoy silently classified the connection as raw TCP.

Envoy's built-in OpenTelemetry tracer, however, requires the connection to be correctly identified as HTTP/2 in order to properly frame gRPC messages.

This mismatch meant the TCP connection succeeded, but every attempt to actually send data failed immediately.

---

## 🟢 4. Final Fix

The `otel-energy-router` service port name was changed from `otlp-grpc` to `grpc-otlp` (i.e., prefixed with `grpc-`):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: otel-energy-router
  namespace: observability-energy-group
spec:
  selector:
    app: otel-energy-router
  ports:
    - name: grpc-otlp   # previously: otlp-grpc
      port: 4317
      targetPort: 4317
````

Immediately after this change (no restart of consuming pods required), Istio correctly detected the protocol, and spans began successfully flowing to both destinations — the central Jaeger and the Energy team's dedicated Jaeger.

---

## 🟢 5. Conclusions and Takeaways

The intermediary OTel Collector fan-out pattern is valid and workable and is a standard way to work around Envoy's single-tracing-provider-per-route limitation in Istio.

Whenever defining a new Service that sits on the mesh data path in Istio, the port name must always be prefixed with the correct protocol identifier (`grpc-`, `http-`, `http2-`, `tcp-`, `tls-`).

Otherwise, Istio defaults to treating the connection as raw TCP, and this misconfiguration doesn't surface as a clear error in the logs — it manifests only as a silent failure at the request level.

A low sampling rate (`randomSamplingPercentage`) can easily be misread as "the pipeline is broken" when testing with low traffic volume.

During testing, it's best to temporarily set it to 100% and revert to the intended production value afterward.

For troubleshooting Istio tracing pipelines, the most effective tools, in order of usefulness, are:

1. The sidecar's `config_dump` (to confirm which provider is actually applied).
2. The Envoy admin port's `/clusters` and `/stats` endpoints (to confirm network- and protocol-level connection health).
3. The Collector's own metrics (`otelcol_exporter_sent_spans` / `send_failed_spans`).


