
📝 **Technical Report: Automatically Detecting Redis Master Pod in Kubernetes and Updating Labels**


### 🔍 **Initial Problem**

In a Redis Sentinel setup, during **failover** (when the current Master becomes unavailable), Sentinel automatically promotes another pod to become the new Master.

However:

* Kubernetes has no built-in mechanism to detect which pod is currently the Master.
* Therefore:

  * The actual Master pod is unknown to Kubernetes.
  * Services that rely on connecting to the Master can’t correctly target it using labels or selectors.

This leads to connectivity issues or potential data inconsistency if a client connects to a replica instead of the Master.

---

# 🎯 **Goal**

This Bash script (setLabel.sh) is designed to **automatically detect the Redis Master pod** in a Kubernetes cluster using Sentinel.
It connects to Sentinel, identifies the current Master pod, and labels it with `master=true`.
It also removes this label from all other Redis pods, ensuring that **only the actual Master pod is labeled** at any time.

This makes it possible for services that need to connect to the Master to use a Kubernetes Service with a selector like `master=true`.

---

# ✅ **Implemented Solution**

The script (setLabel.sh file) solves this by querying Sentinel using `redis-cli` to get the current Master’s IP and resolving it back to a pod name:

```
🧩  kubectl exec -n "$NAMESPACE" "$POD_NAME" -c "$CONTAINER" -- sh -c "redis-cli -h $SENTINEL_HOST -p $SENTINEL_PORT <<EOF
    AUTH $REDIS_PASSWORD
    SENTINEL get-master-addr-by-name $MASTER_NAME
    EOF"
```

Then:

1. It checks whether that pod already has the label `master=true`.
2. If not, it updates the label for the new Master.
3. It removes the `master` label from all other Redis pods in the namespace.

This ensures that at any given time, only the current Master pod has the label.

---

# ⏱️ **Scheduled Execution**

Since failover can happen at any moment, the script needs to run periodically.

To achieve that, the script (wrapper.sh file) is executed every minute as a CronJob. Inside that job, the following snippet runs the main script every 15 seconds, 4 times within the minute:

This ensures the detection stays up to date, roughly within 15 seconds of a failover.


------


### ⚙️ **Next Steps After Labeling the Master**

Once the Redis Master pod is correctly labeled, the following steps are needed to make it usable by applications:

💻 Create a Kubernetes Service with Label Selector

1. You should define a new service (service-setlabel.yaml --> expose-redis-master) in the same namespace that selects the Redis pod with the label `master=true`, like this:

2. Alternatively, if you're using a Helm chart for Redis Sentinel, you can **modify the chart values** to add the `master=true` label on the correct service.


💻 Update Your Application Configuration

In your application (e.g., .NET, Java, etc.), you should point the Redis connection string to the **name of the service that selects the Master**, like:

```
🧩 "Redis": "expose-redis-master.redis-sentinel-test.svc.cluster.local:6379,password=----,ssl=False,allowAdmin=true",
```

This ensures that the app always connects to the correct Redis Master after failover.

---

# ✅ Expose Port 6379 If Needed

If external clients (outside the cluster) need to connect to Redis, you must expose **port 6379** on ingress-nginx

This will expose the Redis Master on port 6379 and make it accessible from outside the cluster, while still maintaining failover logic internally.
