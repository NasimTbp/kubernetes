### Technical Report: Temporal on Kubernetes 
---

## 🎯 1) What is Temporal?

**Temporal is a workflow orchestration engine**. It is designed to run *multi-step, long-running business processes* reliably.

What Temporal provides:

* **Durable execution** of workflows (the process continues even if pods restart)
* Built-in **retry / timeout / backoff** handling
* **Timers / delays / scheduling** without relying on external cron
* Full **execution history** for debugging and audit
* Routing and dispatching work to application **workers**

> Important: Temporal does **not** run your business logic by itself. Your business logic runs in your **application Workers**. Temporal manages orchestration, state, queues, and history.

---

## 🎯 2) What is a Workflow?

In Temporal, a **Workflow** is the code definition (function/class) of a step-by-step process. It describes *the order and logic* of the process.

* A Workflow mostly does **orchestration** (decisions, sequencing)
* The actual external work (DB calls, HTTP/gRPC, RabbitMQ, etc.) is typically implemented as **Activities**

Mental example:

> “Create request → retry on failure → wait for approval → process payment → send notification”

Key facts:

* Workflows run inside a **Temporal Namespace**
* Workflow tasks are routed through a **Task Queue**
* Your application **Worker** polls that Task Queue and executes Workflow/Activity code
* The UI shows workflow status and full event history

---

## 🎯 3) Temporal services/pods in our cluster (brief)

In the `temporal` Kubernetes namespace we have the following components:

🔹 `temporal-frontend` (Service/Pod): The **main gRPC entrypoint** for SDK clients and application workers.
Anything that connects to Temporal should connect here.

```
* Correct in-cluster address: `temporal-frontend.temporal.svc.cluster.local:7233`
```

🔹 `temporal-history` (Pod + headless svc): Responsible for **workflow state and event history** (the durable event log that powers determinism and recovery).

🔹 `temporal-matching` (Pod + headless svc): Responsible for **Task Queues** and delivering tasks to workers that poll those queues.

🔹 `temporal-worker` (Pod + headless svc): This is an **internal worker of the Temporal server** (not your application worker). It runs internal background/system tasks for the Temporal server.

🔹 `temporal-postgres-postgresql` (StatefulSet/Pod + svc): The **persistence database** (PostgreSQL). Workflow state and history are stored here.

🔹 `temporal-schema-*` (Job): A job that **initializes/migrates the Temporal DB schema**.

🔹 `temporal-admintools` (Pod): Administrative CLI container used for operations like:

* listing/creating **Temporal Namespaces**
* basic admin/debug commands

🔹 `temporal-web` (Service/Pod): The **Temporal Web UI** (in our setup exposed via ingress, running on port 8080).

---

## 🎯 4) What is the UI used for?

The Temporal Web UI is mainly for **visibility and debugging**:

* list workflow executions
* search/filter by WorkflowId, status, time, etc.
* inspect full **event history** (where it failed, retries, activity failures, waiting states, etc.)

Notes:

* UI is generally **not** where you “create” task queues.
* Namespace creation is typically done via CLI (`admintools`), not via UI.

---

## 🎯 5) How to create/prepare these items?

### 5.1 Create the Temporal Namespace (e.g., `BffService`)

Using `temporal-admintools`:

```bash
kubectl exec -it -n temporal temporal-admintools-... -- bash

temporal operator namespace create \
  --address temporal-frontend.temporal.svc.cluster.local:7233 \
  --namespace BffService \
  --retention 168h
```

**Retention** in Temporal is the period of time that Temporal keeps data for **closed workflow executions** (e.g., Completed/Failed/Terminated), including their **event history and metadata**, so you can view them in the Web UI, search them, and use them for debugging/auditing. After this retention window, Temporal may **clean up (garbage-collect)** those closed executions to prevent the persistence database from growing indefinitely. Retention **does not expire the Namespace**, and it does **not stop or affect running workflows**—it only controls how long finished executions remain stored and visible.

### 5.2 How is the Task Queue created?

A Task Queue is not something you manually “create” in the UI. It becomes active when:

* your application worker starts polling that queue, and/or
* workflows produce tasks targeting that queue

So the key requirement is: **your worker must be running**, and must use the **same Namespace and TaskQueue** values.

### 5.3 After updating the ConfigMap

Since configuration is stored in a ConfigMap, pods typically need a restart to apply it:

* `kubectl rollout restart deploy/<app> -n <app-ns>`

---

## 🎯 6) Practical notes (important for newcomers to Temporal)

* An empty UI does not necessarily indicate a problem. You might be viewing the `default` Temporal namespace while workflows run in `BffService`.
* If a workflow is started but does not progress, the usual causes are:

  * **no worker running**, or
  * **TaskQueue mismatch** (worker polls a different queue name)
* There are two different “namespaces”:

  * Kubernetes namespace (`temporal`)
  * Temporal namespace (`default`, `BffService`, etc.)

---
