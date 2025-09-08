Report: Path Rewriting in NGINX Ingress and the Role of $2

## 1. Introduction

In Kubernetes, the Ingress resource is responsible for routing external requests to internal services. One of the key features of Ingress in the NGINX Ingress Controller is the ability to rewrite request paths using the following annotation:

🧩 nginx.ingress.kubernetes.io/rewrite-target 

This feature allows parts of the incoming request path to be removed or modified, so that only the relevant portion is passed to the backend service. This report explains the meaning of $2 in this configuration and discusses how PathType works.

## 2. Problem Definition

In the following configuration, the rewrite target is defined as / $2:

🧩 nginx.ingress.kubernetes.io/rewrite-target: /$2 

The corresponding path is defined as:

🧩 - path: /XXXapi(/|$)(.*) pathType: ImplementationSpecific 

The main question is: what does $2 represent, and why is ImplementationSpecific used as the PathType?

## 3. Regex Path Analysis

The path pattern /XXXapi(/|$)(.*) works as follows:

🔹 /XXXapi → the path must start with this literal string.

🔹 (/|$) → Capture Group 1 → matches either a / or the end of the string ($).

🔹 (.*) → Capture Group 2 → matches anything that follows.

## 4. Capture Groups and the Role of $2

Every expression inside parentheses ( … ) in Regex is a Capture Group.

In this case:

🔹 $1 = either / or end of string.

🔹 $2 = whatever comes after /XXXapi/....

When the annotation is defined as:

🧩 nginx.ingress.kubernetes.io/rewrite-target: /$2 

It means only the content of the second group ($2) is included in the rewritten path. As a result, the fixed prefix /XXXapi is removed, and only the variable part of the path is forwarded to the backend service.


## 5. PathType and the Role of ImplementationSpecific

Ingress supports three types of PathType:

Exact → the path must exactly match the incoming request.

Prefix → the path must match the beginning of the request, and sub-paths are also accepted.

ImplementationSpecific → path matching behavior depends on the Ingress controller implementation.

In the NGINX Ingress Controller, ImplementationSpecific allows the use of regular expressions (Regex). This enables advanced patterns like (/|$)(.*) for matching paths and extracting capture groups.

That is why ImplementationSpecific is used in this example—other PathTypes like Prefix do not support Regex-based matching or group extraction ($2).

## 6. Conclusion

Using $2 in path rewriting ensures that the fixed prefix /XXXapi is removed from incoming requests, and only the dynamic portion of the path is passed to the backend. This provides more flexibility in route design.

Furthermore, setting PathType = ImplementationSpecific enables the use of Regex in path definitions, while Exact and Prefix do not. For scenarios that require complex matching and advanced rewriting, this choice is essential.

