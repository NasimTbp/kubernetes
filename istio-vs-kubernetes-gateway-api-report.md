# 🎯 Report: Istio, Kubernetes Gateway API, and API Groups

## 🧩 Introduction

When traffic comes from outside a Kubernetes cluster and needs to reach an application inside the cluster, there must be an entry point that receives the traffic and forwards it correctly. In modern Kubernetes networking, that entry point is often described using a `Gateway`. The reason you may see two different kinds of `Gateway` is that they belong to two different APIs: one is the Istio-specific API, and the other is the standard Kubernetes Gateway API. Even though both resources are named `Gateway`, they are not the same thing because they come from different API groups. 

## 🧩 What Istio is

Istio is a service mesh for Kubernetes. It adds a programmable networking layer for service-to-service communication and edge traffic management. In practice, Istio is used for traffic routing, retries, timeouts, resilience features, policy enforcement, telemetry, and security features such as mTLS. Istio describes itself as an application-aware networking layer for modern distributed systems. 

## 🧩 What Kubernetes Gateway API is

Kubernetes Gateway API is a standard Kubernetes networking API designed for advanced traffic routing and dynamic infrastructure provisioning. It is intended to be more expressive, role-oriented, and extensible than the older Ingress model, and it is designed to be implemented by many different controllers, not only one vendor or project. 

## 🧩 What an API group is

In Kubernetes, resources are organized into API groups. An API group is a family of related resources, and it appears in the `apiVersion` field of a YAML object as well as in the Kubernetes REST API path. Kubernetes documents this explicitly: API groups make the API easier to extend, and the group is specified in the REST path and in the `apiVersion` field of serialized objects. 


In Kubernetes, `apiVersion` usually has the form:

`<group>/<version>`

or, for core resources, simply:

`<version>` 

## 🧩 Why you see two different kinds of Gateway

You see two kinds of `Gateway` because there are two different configuration languages, or more precisely, two different APIs.

One is the Istio-specific API:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
```

The other is the standard Kubernetes Gateway API:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
```

📍📍 The resource name is the same, but the API group is different, so they are two different resource types. Kubernetes Gateway API is a standard, vendor-neutral API, and Istio supports it. Istio also states in its official documentation that, in addition to its own traffic-management API, it supports Kubernetes Gateway API and intends to make it the default API for traffic management in the future. That is why the Istio-specific Gateway should be understood as the older, classic Istio style, while the Gateway API version is the newer standardized direction. 

## 1) Istio Gateway: `networking.istio.io/v1`

When you write:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
```

you are using Istio’s own configuration API. This is the classic Istio traffic-management model. In this model, there is usually already an ingress gateway workload running in the cluster, often an Envoy-based deployment and service. The Istio `Gateway` resource typically configures that existing gateway by specifying which hosts it accepts, which ports it listens on, and how TLS is handled. 

In this model, actual request routing is usually defined in a separate `VirtualService`. So conceptually:

* the Istio `Gateway` is the entry door,
* the `VirtualService` is the routing logic after traffic enters.

That is why the classic Istio pattern is usually:

**Gateway + VirtualService** 

## 2) Kubernetes Gateway API: `gateway.networking.k8s.io/v1`

When you write:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
```

you are using the Kubernetes Gateway API. This is the newer, standardized model. In this architecture, the API is split into several parts:

* `GatewayClass`: defines which controller implements the gateway,
* `Gateway`: defines the actual entry point,
* `HTTPRoute`, `TCPRoute`, `GRPCRoute`, and similar resources: define routing rules. 

So in this model, routing is not usually written in `VirtualService`; instead, it is expressed in dedicated route resources such as `HTTPRoute`. In Istio’s implementation of Gateway API, a `Gateway` can also trigger automatic provisioning of the gateway `Deployment` and `Service`, so you do not always need to create and manage those manually. Istio documents this explicitly for Gateway API. 

Conceptually:

* the Gateway API `Gateway` is the entry door,
* `HTTPRoute` and related route resources are the routing rules after entry.

So the common pattern here is:

**GatewayClass + Gateway + HTTPRoute/TCPRoute** 


## 🧩 The most important conceptual difference

The deepest difference is not just the YAML syntax. It is the architectural model.

In the Istio-specific model, traffic management is described with Istio-native resources such as `Gateway` and `VirtualService`.

In the Kubernetes Gateway API model, traffic management is described with standardized Kubernetes resources such as `GatewayClass`, `Gateway`, and `HTTPRoute`. 

```
In the Kubernetes Gateway API model, traffic management is split across a few standardized Kubernetes resources instead of being described in one place: `GatewayClass` tells Kubernetes which controller or implementation is responsible for managing the gateway, `Gateway` defines the actual traffic entry point by specifying things like listeners, ports, protocols, and hostnames, and `HTTPRoute` defines how incoming HTTP requests should be matched and forwarded to backend services; in other words, `GatewayClass` says who manages the door, `Gateway` is the door itself, and `HTTPRoute` is the rule that says where each request goes after it enters.
```

So although both resources are called `Gateway`, they belong to different API groups and are part of different configuration ecosystems.
