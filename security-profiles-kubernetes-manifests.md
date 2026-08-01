# 🎯 Security Profiles for Kubernetes Manifests

## Introduction

Running workloads in Kubernetes without appropriate security restrictions can increase the risk of privilege escalation, unauthorized access to node resources, and container escape.

The purpose of defining a security profile in Kubernetes manifests is to ensure that each container receives only the permissions and access required to run correctly. This approach follows the principle of least privilege.

## 1. Disable Automatic Service Account Token Mounting

By default, Kubernetes may automatically mount a ServiceAccount token inside a Pod. This token can be used to communicate with the Kubernetes API.

If the application does not need access to the Kubernetes API, automatic token mounting should be disabled:

```yaml
spec:
  automountServiceAccountToken: false
```

This configuration reduces the risk of ServiceAccount token abuse if the container is compromised.

## 2. Use a Seccomp Profile

Seccomp is a Linux security mechanism that restricts the system calls a process can make to the kernel.

Kubernetes supports three main `seccompProfile` types.

### RuntimeDefault

```yaml
securityContext:
  seccompProfile:
    type: RuntimeDefault
```

This option uses the default seccomp profile provided by the container runtime. It blocks or restricts several dangerous and unnecessary system calls.

`RuntimeDefault` is recommended for most applications.

### Unconfined

```yaml
securityContext:
  seccompProfile:
    type: Unconfined
```

This option disables seccomp restrictions. The process can use all system calls available to the container.

This mode is not recommended for production workloads.

### Localhost

```yaml
securityContext:
  seccompProfile:
    type: Localhost
    localhostProfile: profiles/custom-profile.json
```

This option uses a custom seccomp profile stored on the Kubernetes node.

It provides more precise control, but the profile must be distributed and maintained on every node where the Pod may run.

## 3. Prevent Privileged Container Execution

Running a container with the following setting is highly dangerous:

```yaml
securityContext:
  privileged: true
```

A privileged container receives extensive access to the host kernel, devices, and Linux capabilities. In practice, the security boundary between the container and the node becomes significantly weaker.

For normal application workloads, the recommended configuration is:

```yaml
securityContext:
  privileged: false
```

Only specific and carefully controlled infrastructure workloads should run in privileged mode.

## 4. Prevent Privilege Escalation

The `allowPrivilegeEscalation` setting determines whether a process inside the container can gain more privileges than its parent process.

The recommended configuration is:

```yaml
securityContext:
  allowPrivilegeEscalation: false
```

This prevents privilege escalation through mechanisms such as `setuid` or `setgid` binaries.

Even if a process initially runs with limited privileges, setting this field to `true` may allow it to gain additional permissions.

## 5. Prevent Access to Host Namespaces

### hostNetwork

```yaml
spec:
  hostNetwork: false
```

When `hostNetwork` is set to `true`, the Pod uses the network namespace of the Kubernetes node.

This gives the container greater visibility and access to the host network.

### hostPID

```yaml
spec:
  hostPID: false
```

When `hostPID` is enabled, processes inside the container can view processes running on the host.

This may be useful for specific monitoring or debugging tools, but it should not be enabled for standard applications.

### hostIPC

```yaml
spec:
  hostIPC: false
```

When `hostIPC` is enabled, the Pod shares the host IPC namespace and may access host inter-process communication resources and shared memory.

The recommended configuration for normal workloads is:

```yaml
spec:
  hostNetwork: false
  hostPID: false
  hostIPC: false
```

## 6. Manage Volume Permissions with fsGroup

The `fsGroup` setting assigns a group ID to mounted volumes so that non-root processes inside the Pod can access or write to them.

Example:

```yaml
spec:
  securityContext:
    fsGroup: 1000
```

This is useful when an application runs as a non-root user but still needs write access to mounted volumes.

### fsGroupChangePolicy

Kubernetes supports two main policies.

#### Always

```yaml
fsGroupChangePolicy: Always
```

Kubernetes checks and updates the group ownership of volume files whenever the volume is mounted.

For large volumes, recursive ownership changes may increase Pod startup time.

#### OnRootMismatch

```yaml
fsGroupChangePolicy: OnRootMismatch
```

Kubernetes changes ownership only when the root directory of the volume does not already have the expected ownership.

This option usually provides better performance for large volumes:

```yaml
spec:
  securityContext:
    fsGroup: 1000
    fsGroupChangePolicy: OnRootMismatch
```

## 7. Restrict Linux Capabilities

Linux capabilities divide root privileges into smaller and more specific permissions.

Instead of granting full root access to a process, Kubernetes can grant only the capabilities required by the application.

A secure default is to remove all capabilities:

```yaml
securityContext:
  capabilities:
    drop:
      - ALL
```

If the application requires a specific capability, it can be added explicitly:

```yaml
securityContext:
  capabilities:
    drop:
      - ALL
    add:
      - NET_BIND_SERVICE
```

For example, `NET_BIND_SERVICE` allows a process to bind to ports below `1024` without granting full root privileges.

Powerful capabilities such as `SYS_ADMIN` should be avoided because they provide broad access to kernel operations.

## 8. Linux Capability Sets

The capability sets of a running process can be viewed using:

```bash
cat /proc/self/status | grep Cap
```

or:

```bash
grep Cap /proc/self/status
```

The output includes several capability sets.

### CapInh

`CapInh` represents the inheritable capability set.

It defines capabilities that may be inherited by a new process under specific conditions when another executable is started.

### CapPrm

`CapPrm` represents the permitted capability set.

It defines the maximum capabilities that the process is allowed to activate.

### CapEff

`CapEff` represents the effective capability set.

These are the capabilities currently active and used by the kernel when checking process permissions.

### CapBnd

`CapBnd` represents the capability bounding set.

It defines the maximum capabilities that the process and its child processes may receive.

A capability removed from the bounding set generally cannot be regained.

### CapAmb

`CapAmb` represents the ambient capability set.

It defines capabilities that can be preserved when executing certain non-privileged programs.

## Recommended Security Profile

The following example provides a suitable baseline for most Kubernetes Deployments:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
spec:
  template:
    spec:
      automountServiceAccountToken: false

      hostNetwork: false
      hostPID: false
      hostIPC: false

      securityContext:
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault

      containers:
        - name: sample-app
          image: sample-app:latest

          securityContext:
            privileged: false
            allowPrivilegeEscalation: false

            capabilities:
              drop:
                - ALL
```

## ✅ Conclusion

Security settings in Kubernetes manifests should be explicitly defined instead of relying on default values.

A secure baseline should normally include:

```text
automountServiceAccountToken: false
privileged: false
allowPrivilegeEscalation: false
hostNetwork: false
hostPID: false
hostIPC: false
seccompProfile.type: RuntimeDefault
capabilities.drop: ALL
```

These controls reduce the attack surface of Kubernetes workloads and limit an attacker’s ability to move from a compromised container to the Kubernetes node or API server.


## 🎯 Notice
These security requirements can be enforced consistently across the cluster by using Kyverno policies. Kyverno can validate Kubernetes manifests and prevent the deployment of workloads that do not comply with the required security settings, such as disabling privileged containers, preventing privilege escalation, enforcing the use of approved seccomp profiles, and restricting host namespace access.
