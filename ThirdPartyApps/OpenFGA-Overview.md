# 🎯 OpenFGA Installation and Usage Report

OpenFGA is an open-source service for **fine-grained authorization**. Its main purpose is to move access-control logic out of the application code and into a dedicated authorization service. Instead of hard-coding permissions inside each backend service, we define relationships in OpenFGA and then ask OpenFGA questions such as: “Does this user have this relation or permission on this object?” For example, we can define that `user:alice` is the `owner` of `document:doc1`, and then ask OpenFGA whether Alice is allowed to access that document.


## ⚙️ Deployment Modes

OpenFGA is typically deployed with a **PostgreSQL** or **MySQL** database in **persistent mode**,  allowing access data and relationship models to be stored permanently.

However, in **development or test environments**, it can be run **in-memory (RAM)** for faster setup and easier testing —  
though all data will be **lost on restart**.

🧠 In the current installation, OpenFGA is running successfully. The important confirmation from the logs is:

```text
using 'postgres' storage engine
using 'preshared' authentication
```

This means OpenFGA is no longer using temporary in-memory storage. It is now using PostgreSQL for persistence. Also, authentication is enabled using the `preshared` method, which means every API request must include this header:

```text
Authorization: Bearer <TOKEN>
```

---
## 🧪 OpenFGA Ports
OpenFGA exposes several ports. Port `8080` is the HTTP API port and is the main port used for day-to-day operations such as creating Stores, writing Authorization Models, writing Tuples, and running Check requests. Port `8081` is for the gRPC API. Port `3000` is for the Playground, and port `2112` is for Prometheus metrics.

Although OpenFGA has something called Playground, it is not a fully local UI. When we opened `/playground`, the OpenFGA server returned a small HTML page containing an iframe that loads the real interface from:

```text
https://play.fga.dev/sandbox/
```

So the local `/playground` page depends on external access to `play.fga.dev`. If the browser, network, DNS, proxy, firewall, or corporate internet policy blocks access to that domain, the result can be a blank page or an error such as:

```text
The connection was reset
```

📌 This is why we could not reliably use the Playground UI in our environment.

There is also a security reason not to use the Playground in production. In our setup, OpenFGA uses `preshared` authentication. The built-in Playground can expose the API token inside the generated HTML/iframe URL. Therefore, the Playground should only be used for local testing or debugging and should not be publicly exposed. For production or stable environments, it is better to keep the Playground disabled and use the HTTP API, CLI, or SDK instead.

The correct operational workflow for OpenFGA is API-based. First, we create a **Store**. A Store is the logical place where authorization models and relationship tuples are stored. Then we define an **Authorization Model** inside that Store. After that, we write **Relationship Tuples**, such as `user:alice` being the `owner` of `document:doc1`. Finally, applications use the **Check API** to ask OpenFGA whether a user has a specific relation or permission on an object.

---

## 🖥️ Useful Commands for Working with OpenFGA

### 1. Port-forward the OpenFGA HTTP API

Run this command in one terminal and keep it open:

```bash
kubectl -n openfga port-forward svc/openfga 8080:8080
```

This makes the OpenFGA HTTP API available locally on:

```text
http://localhost:8080
```

---

### 2. Set the API URL and token

In another terminal on the same VM, set these variables:

```bash
export FGA_API_URL="http://localhost:8080"
export FGA_API_TOKEN="CHANGE-THIS-TO-A-LONG-RANDOM-SECRET"
```

`FGA_API_URL` is the local API endpoint.
`FGA_API_TOKEN` is the pre-shared key configured for OpenFGA.

---

### 3. Create a Store

To create a Store named `MyStore`:

```bash
curl -s -X POST "$FGA_API_URL/stores" \
  -H "Authorization: Bearer $FGA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"MyStore"}'
```

Example successful output:

```json
{
  "id": "01KQBY68D1D3D278MPT4ECJEDZ",
  "name": "MyStore",
  "created_at": "2026-04-29T06:17:59.971397Z",
  "updated_at": "2026-04-29T06:17:59.971397Z"
}
```

The `id` is important because most later API calls require the Store ID.

---

### 4. List existing Stores

To verify that the Store was created:

```bash
curl -s "$FGA_API_URL/stores" \
  -H "Authorization: Bearer $FGA_API_TOKEN" | jq
```

Example output:

```json
{
  "stores": [
    {
      "id": "01KQBY68D1D3D278MPT4ECJEDZ",
      "name": "MyStore",
      "created_at": "2026-04-29T06:17:59.971397Z",
      "updated_at": "2026-04-29T06:17:59.971397Z",
      "deleted_at": null
    }
  ],
  "continuation_token": ""
}
```

If `jq` is not installed, the same command can be used without `| jq`.

---

### 5. Save the Store ID in an environment variable

To avoid copying the Store ID manually every time, extract it by Store name:

```bash
export FGA_STORE_ID=$(
  curl -s "$FGA_API_URL/stores" \
    -H "Authorization: Bearer $FGA_API_TOKEN" \
  | jq -r '.stores[] | select(.name=="MyStore") | .id'
)

echo "$FGA_STORE_ID"
```

Example output:

```text
01KQBY68D1D3D278MPT4ECJEDZ
```

After this, `$FGA_STORE_ID` can be used in later commands.

---

### 6. Test API access and authentication

To verify that the API is reachable and the token is accepted:

```bash
curl -i "$FGA_API_URL/stores" \
  -H "Authorization: Bearer $FGA_API_TOKEN"
```

Successful output should include:

```text
HTTP/1.1 200 OK
Content-Type: application/json
```

If the token is missing, OpenFGA returns an error like:

```json
{
  "code": "bearer_token_missing",
  "message": "missing bearer token"
}
```

So every OpenFGA API request must include:

```bash
-H "Authorization: Bearer $FGA_API_TOKEN"
```

---

## Quick Command Block

```bash
# 1. Run this in a separate terminal and keep it open
kubectl -n openfga port-forward svc/openfga 8080:8080
```

```bash
# 2. Set API URL and token
export FGA_API_URL="http://localhost:8080"
export FGA_API_TOKEN="CHANGE-THIS-TO-A-LONG-RANDOM-SECRET"

# 3. Create a Store
curl -s -X POST "$FGA_API_URL/stores" \
  -H "Authorization: Bearer $FGA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"MyStore"}'

# 4. List Stores
curl -s "$FGA_API_URL/stores" \
  -H "Authorization: Bearer $FGA_API_TOKEN" | jq

# 5. Save Store ID
export FGA_STORE_ID=$(
  curl -s "$FGA_API_URL/stores" \
    -H "Authorization: Bearer $FGA_API_TOKEN" \
  | jq -r '.stores[] | select(.name=="MyStore") | .id'
)

# 6. Print Store ID
echo "$FGA_STORE_ID"

# 7. Test API access
curl -i "$FGA_API_URL/stores" \
  -H "Authorization: Bearer $FGA_API_TOKEN"
```

At this point, OpenFGA is ready to use through the API. The next step is to define an Authorization Model, write Relationship Tuples, and then use the Check API to test permissions.





