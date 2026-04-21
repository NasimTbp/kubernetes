### Complete and Summary Report of the Three Commands:

1. **Command 1: Search in ConfigMaps with `grep`**

   * **Command**: `kubectl get configmap --all-namespaces | grep "sms-app"`
   * **Description**: Searches all `ConfigMap` names for the string `"sms-app"`.
   * **Output**: A list of `ConfigMap` names that contain `"sms-app"`.
   * **Example Output**:

     ```bash
     default     sms-app-config
     production  sms-app-settings
     ```

2. **Command 2: Search in `ConfigMap` data with `jq`**

   * **Command**:

     ```bash
     kubectl get configmaps --all-namespaces -o json | jq -r '.items[] | select(.data | tostring | contains("172.17.29.21")) | "Namespace: \(.metadata.namespace)\nConfigMap: \(.metadata.name)\n---"'
     ```
   * **Description**: Searches `ConfigMap` data for the specific IP `"172.17.29.21"`.
   * **Output**: `Namespace` and `ConfigMap` names that contain the IP in their data.
   * **Example Output**:

     ```bash
     Namespace: default
     ConfigMap: sms-app-config
     ---
     Namespace: production
     ConfigMap: sms-app-settings
     ---
     ```

3. **Command 3: Search in all cluster resources with `jq`**

   * **Command**:

     ```bash
     kubectl get all --all-namespaces -o json | jq -r '.items[] | select(tostring | contains("172.17.29.21")) | "Namespace: \(.metadata.namespace)\nResource: \(.kind)\nName: \(.metadata.name)\n---"'
     ```
   * **Description**: Searches all cluster resources (pods, services, deployments, etc.) for the IP `"172.17.29.21"`.
   * **Output**: `Namespace`, resource type, and resource name for those that contain the IP in any part of the object.
   * **Example Output**:

     ```bash
     Namespace: default
     Resource: Pod
     Name: my-pod
     ---
     Namespace: kube-system
     Resource: Service
     Name: kube-dns
     ---
     Namespace: production
     Resource: Deployment
     Name: app-deployment
     ---
     ```

### Summary:

* **Command 1**: Lists `ConfigMap` names that contain the string `"sms-app"`.
* **Command 2**: Lists `ConfigMap` names that contain the IP `"172.17.29.21"` in their data.
* **Command 3**: Searches all cluster resources for the IP `"172.17.29.21"` in any part of the resource.

This report includes all the details and outputs related to each command.
