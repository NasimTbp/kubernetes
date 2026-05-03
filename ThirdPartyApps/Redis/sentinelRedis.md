## 📌 Why Redis Sentinel Was Used

The team deployed Redis with Sentinel to ensure high availability and minimize service disruptions in case of failures. Sentinel serves three critical purposes:

✅ Monitoring the Master Node

 Sentinel continuously monitors the Redis master node to detect any failures or unresponsiveness.

✅ Automatic Failover

 If the master node becomes unavailable, Sentinel automatically promotes one of the replica nodes to become the new master. This ensures Redis remains operational without requiring manual intervention.

✅ Informing Clients of the New Master

 Sentinel helps client applications discover the current master’s address so they can always connect to the correct Redis node, even after a failover.

-----

## Understanding Master and Replica Roles

To verify which Redis nodes are acting as master or replicas, the following commands were executed inside the Redis pods:

```
redis-cli
AUTH <password>
INFO replication
```

-----

## `serviceName` in Redis Sentinel with StackExchange.Redis

In the context of **StackExchange.Redis** and a **Redis Sentinel** setup, the `serviceName` parameter in the "connectionString" defines the **name of the Redis master group** (also known as the "master set") that Sentinel manages.

Redis Sentinel ensures **high availability (HA)** by:

* Monitoring Redis instances
* Handling automatic failover
* Providing clients with the address of the current master node

The `serviceName` is what StackExchange.Redis uses to identify **which master group to query** when contacting Sentinel.

---

✅ How to Find the `serviceName`

1. Connect to a Sentinel instance using `redis-cli`:

```
redis-cli -h test-sentinel-redis.redis-sentinel-test.svc.cluster.local -p 26379
```

2. AUTH

3. Run the following command:

```
SENTINEL masters
SENTINEL slaves mymaster
```

💻 This will list all master/Replica groups monitored by Sentinel.


🔗 Look for the `name` field in the output. This value is the `serviceName`.

**Example output:**

🧩
1) "name"
2) "mymaster"
...

🧩

In this case, the `serviceName` is: 📍 mymaster

---
✅ Check Extra Common configuration (added in common.conf)

```
CONFIG GET min-replicas-to-write
```

💻  This will show the 'min-replicas-to-write' config's value stored in common.conf file

```
ACL LIST
```

💻 In Redis returns a list of all Redis users along with their Access Control List (ACL) rules.
💻 The output contains one string per user, describing that user’s configuration and permissions.


---

✅ Adding serviceName TO ConnectionString

Then, you need to add the serviceName to your connection string like this:

```
"ConnectionString": "test-sentinel-redis.redis-sentinel-test.svc.cluster.local:26379,password=----,serviceName=mymaster,ssl=False,allowAdmin=true",
```

---

✅ Changing serviceName In helm chart

You can also set serviceName in the helm chart configuration in override as follows:

```
sentinel:
  masterSet: mymaster
```

-----
