# this directory is for node-exporter configs that scraps external nodes inside Devops env.

Note:

💻 Steps 1 to 4 (downloading, extracting, moving the binary, and creating the systemd service) must be executed on each node where you want to install Node Exporter.
💻 The remaining steps (creating the Service, Endpoint, and ServiceMonitor) should be performed on the Kubernetes master node (or from wherever you manage the cluster configuration).
💻 After completing all the steps, within a few minutes, any node where Node Exporter was installed and started will automatically appear under the Targets section in Prometheus.

---

## ✅ **Node Exporter Setup Report for Prometheus Monitoring**

### 📌 Step 1: Download Node Exporter

The Node Exporter (version 1.9.1) was downloaded using the following link:


https://release-assets.githubusercontent.com/.../node_exporter-1.9.1.linux-amd64.tar.gz


### 📁 Step 2: Extract and Move the Binary

The following commands were executed:

🧩 tar -zxvf node_exporter-1.9.1.linux-amd64.tar.gz
🧩 sudo mv node_exporter-1.9.1.linux-amd64/node_exporter /usr/local/bin/

🔗 > Note: There was a typo referring to version 1.8.2 earlier, which was corrected to the correct version 1.9.1.

---

### ⚙️ Step 3: Create a systemd Service

A new systemd service file named `node-exporter.service` was created:


🧩 sudo nano /etc/systemd/system/node-exporter.service

With the following content:

🧩-------------------------------------🧩

[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=nobody
ExecStart=/usr/local/bin/node_exporter --collector.systemd --collector.systemd.unit-whitelist="(keepalived|ssh|haproxy|cron|NetworkManager|node-exporter|rsyslog|system-resolved).service"
Restart=always

[Install]
WantedBy=multi-user.target

🧩-------------------------------------🧩

💡 *Note*: The `--collector.systemd.unit-whitelist` flag ensures that only selected systemd services are monitored.

---

### 🔄 Step 4: Enable and Start the Service

The following commands were used to enable and start Node Exporter:

🧩 sudo systemctl daemon-reload
🧩 sudo systemctl enable node-exporter
🧩 sudo systemctl restart node-exporter


✅ At this point, the service was successfully running and available on port `:9100`.

---

### 🌐 Step 5: Connect to Prometheus (Kubernetes Integration)

To allow Prometheus to scrape metrics from the Node Exporter, the following Kubernetes resources were created:

* **Service**
* **Endpoints**
* **ServiceMonitor**

The YAML configuration files for these resources are located in:

💻💻 /root/k8s-deployments/prometheus-manual-configs/external-vms-monitor/configs.yaml

📌 These allow Prometheus to discover and scrape the Node Exporter either from outside the cluster or via a defined static endpoint or NodePort.
📌 In the Endpoint YAML file, you need to add the IP address of the VM where Node Exporter is installed, so that Prometheus can scrape metrics from it.

---

## 🟢 Conclusion

Node Exporter was successfully installed and configured. Using a specific whitelist for systemd units, only relevant services are being monitored.
The setup is now ready for Prometheus to collect metrics via the configured `ServiceMonitor`, and these metrics can also be visualized in Grafana dashboards.

---
