# 🎯 Report: Storage Migration (NFS → VMFS) and PVC Data Transfer for `nop-app-hotfix`

## 🧩 1) Background (Before vs After)

### Before

The `nop-app-hotfix` or `x` application was running with **NFS-backed storage**. The application data (e.g., `wwwroot`, `App_Data`) was persisted on a PVC, and the Deployment consumed that data via specific volume mounts.

### After

Storage was migrated to **VMFS (vSphere/VMFS datastore)**. With the new backend, the PVC/PV became effectively “new” from the application’s perspective (empty or missing the expected data structure). Therefore, the application could not start correctly until the required files were placed back into the PVC in the correct paths.

---

## 🧩 2) Problem Statement

After the storage migration (NFS → VMFS), the application required its previous data to exist on the PVC using the same directory structure as before.

The original Deployment used the following mounts:

```yaml
volumeMounts:
- name: wwwroot-file
  mountPath: /app/wwwroot
  subPath: wwwroot
- name: app-data
  mountPath: /app/App_Data
  subPath: App_Data
- name: appsettings-volume
  mountPath: /app/App_Data/appsettings.json
  subPath: appsettings.json
```

Therefore, the PVC content must ultimately provide these paths for the running container:

* `/app/wwwroot/...`
* `/app/App_Data/...`
* `/app/App_Data/appsettings.json`

---

## 🧩 3) Chosen Approach (Safe and Repeatable)

To restore/copy the required files into the VMFS-backed PVC, a temporary **migration/writer pod** was created. This pod mounts the target PVC and stays running so that files can be transferred into the mounted path using `kubectl cp`. After the copy is finished, the migration pod is removed and the main application Deployment is brought back up.

**Why this approach:**

* No direct access to the underlying datastore is needed
* Works regardless of storage type (NFS, VMFS, etc.)
* Ensures files are placed exactly where the application will see them at runtime

---

## 🧩 4) Implementation Steps

### 🔹 Step 1 — Scale down / stop the main application

The main application was taken down (e.g., scaled to 0 replicas or the Deployment was stopped) to avoid any concurrent writes while restoring the PVC content.
#### 📌 change storageClass from nfs to vmfs

---

### 🔹 Step 2 — Create a temporary pod that mounts the PVC

A simple Alpine pod was created that mounts the application PVC at `/app` and sleeps to remain available for copy operations:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pvc-writer
  namespace: nop-app-hotfix
spec:
  restartPolicy: Never
  containers:
    - name: writer
      image: repo.acctechco.com:8445/alpine:3.20
      command: ["sh", "-c"]
      args:
        - |
          echo "PVC mounted at /app";
          echo "Ready for kubectl cp...";
          sleep 3650000
      volumeMounts:
        - name: data
          mountPath: /app
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: nop-app-hotfix-pvc
```

After applying this manifest, the pod was waited on until it became `Running`.

---

### 🔹 Step 3 — Copy files into the PVC using `kubectl cp`

Once the migration pod was running, required files were copied from the admin environment (e.g., master node or local machine where the files were available) into the mounted PVC path:

```bash
kubectl -n nop-app-hotfix cp <LOCAL_PATH> pvc-writer:/app
```

---

## 🧩 5) Critical Notes About Paths (Very Important)

### A) The PVC directory structure must match what the app expects

Because the application expects `/app/wwwroot` and `/app/App_Data`, the files must be copied into the PVC such that these paths exist when the main Deployment starts.

### B) Common mistake: accidentally creating `/app/app`

If you copy an entire top-level folder named `app` into `/app`, you may end up with:

* Wrong result: `/app/app/...`

In that case, the application will not find files in the expected locations.

**Correct approach:**

* Copy **only the contents** of the `app` directory into `/app`, **not** the directory itself; or
* If `/app/app` was created by mistake, move the contents one level up (from `/app/app/*` to `/app/`).

---

## 🧩 6) Cleanup and Restore Service

After confirming the data was copied correctly:

1. The temporary `pvc-writer` pod was removed.
2. The main application Deployment was started/scaled up again.

The application reattached to the same PVC and could access the restored files, allowing it to start normally.

---

## 🧩 7) Suggested Validation Checklist

To confirm the migration/restore is correct, verify that these exist inside the mounted PVC:

* `/app/wwwroot/`
* `/app/App_Data/`
* `/app/App_Data/appsettings.json`

This can be checked either in the migration pod (before deletion) or in the main application pod after startup.
