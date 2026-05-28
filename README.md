# LKE-E ACL Operator

Enterprise-grade Kubernetes automation for dynamically managing  
LKE Enterprise (LKE-E) Control Plane ACLs on Akamai Connected Cloud (Linode).

---

# 🚀 Problem Statement

LKE Enterprise (LKE-E) allows restricting Kubernetes API server access using Control Plane ACLs.

However, Kubernetes worker nodes in autoscaling environments may:

- Scale up dynamically
- Recycle during upgrades
- Change public IP addresses
- Join/leave the cluster automatically

This creates a major operational challenge:

❌ Manual ACL management  
❌ Failed kubectl access from workloads  
❌ Broken automation pipelines  
❌ Race conditions during node scaling  
❌ Security gaps from stale ACL entries

---

# ✅ What This Solution Does

The LKE-E ACL Operator automatically:

✔ Detects worker node public IPs  
✔ Adds worker node IPs into LKE-E Control Plane ACL  
✔ Prevents duplicate/race-condition ACL updates  
✔ Applies readiness labels after ACL registration  
✔ Removes startup taints after successful ACL registration  
✔ Cleans stale node IPs from ACL periodically  
✔ Preserves permanent static CIDRs (VPN/Bastion/Office IPs)  
✔ Works with autoscaling node pools  
✔ Supports enterprise-grade logging and reconciliation

---

# 🏗️ Architecture

text +-------------------------------------------------------+ |                  LKE-E Control Plane                  | |                   Control Plane ACL                   | +-------------------------+-----------------------------+                           ^                           |                   Linode API (PUT ACL)                           | +-------------------------------------------------------+ |                 LKE-E ACL Operator                    | |                                                       | |  +-------------------+    +------------------------+  | |  | ACL Agent         |    | ACL Reconciler        |  | |  | (DaemonSet)       |    | (CronJob)             |  | |  +-------------------+    +------------------------+  | |          |                            |               | |          |                            |               | |  Runs on every node         Removes stale node IPs   | |  Adds node IP to ACL        Preserves static CIDRs   | |                                                       | +-------------------------------------------------------+ 

---

# 🔄 Operational Workflow

## ACL Agent (DaemonSet)

Each worker node runs one ACL Agent pod.

### Workflow

1. Detect node ExternalIP
2. Convert IP to /32
3. Acquire distributed ACL update lock
4. Fetch current ACL
5. Merge:
   - Existing ACL IPs
   - Static CIDRs
   - Current node IP
6. Update LKE-E ACL
7. Verify ACL update success
8. Label node as ACL-ready
9. Remove startup taint

---

## ACL Reconciler (CronJob)

Runs periodically to:

- Detect active worker node IPs
- Remove stale node IPs
- Preserve static CIDRs
- Ensure ACL consistency

---

# 🔐 Distributed Locking

To prevent concurrent ACL corruption during autoscaling events:

✔ ConfigMap-based distributed lock  
✔ Stale lock detection  
✔ Automatic lock recovery  
✔ Safe concurrent scaling behavior

---

# 📦 Components

| Component | Purpose |
|---|---|
| Namespace | Isolated operator deployment |
| ConfigMap | Runtime configuration |
| Secret | Linode API token |
| RBAC | Kubernetes permissions |
| ACL Agent | Node-level ACL registration |
| ACL Reconciler | Periodic ACL cleanup |
| ConfigMap Script Loader | Runtime script updates |

---

# 📁 Repository Structure

text . ├── manifests/ │   ├── 00-namespace.yaml │   ├── 01-configmap.yaml │   ├── 02-secret.example.yaml │   ├── 03-rbac.yaml │   ├── 04-daemonset-acl-agent.yaml │   └── 05-cronjob-acl-reconciler.yaml │ ├── scripts/ │   ├── acl-agent.sh │   ├── acl-reconciler.sh │   └── create-script-configmaps.sh │ ├── Dockerfile ├── README.md └── .gitignore 

---

# ⚙️ Configuration

## Example ConfigMap

yaml STATIC_ACL_CIDRS: "203.0.113.10/32,198.51.100.20/32" LOG_LEVEL: "INFO" RECONCILE_INTERVAL_SECONDS: "300" 

---

# 📝 Supported Log Levels

| Level | Description |
|---|---|
| DEBUG | Verbose troubleshooting logs |
| INFO | Standard operational logs |
| WARN | Warning messages |
| ERROR | Error messages only |

---

# 🚀 Deployment

## 1. Create Namespace

bash kubectl apply -f manifests/00-namespace.yaml 

---

## 2. Create Secret

bash cp manifests/02-secret.example.yaml secret.yaml 

Update:

yaml LINODE_TOKEN: "<YOUR_TOKEN>" 

Apply:

bash kubectl apply -f secret.yaml 

---

## 3. Apply Configuration

bash kubectl apply -f manifests/01-configmap.yaml 

---

## 4. Apply RBAC

bash kubectl apply -f manifests/03-rbac.yaml 

---

## 5. Create Script ConfigMaps

bash ./scripts/create-script-configmaps.sh 

---

## 6. Deploy ACL Agent

bash kubectl apply -f manifests/04-daemonset-acl-agent.yaml 

---

# 🔎 Validation

## Check ACL Agent Logs

bash kubectl logs -n lke-acl-operator -l app=lke-acl-agent -f 

---

## Verify Node Labels

bash kubectl get nodes --show-labels 

---

## Verify ACL Entries

bash curl -H "Authorization: Bearer <TOKEN>" \ https://api.linode.com/v4/lke/clusters/<CLUSTER_ID>/control_plane_acl 

---

# 📌 Best Practices

✔ Use startup taints to block premature workload scheduling  
✔ Use static CIDRs for VPN/Bastion/Admin access  
✔ Use LOG_LEVEL=INFO in production  
✔ Keep reconciliation interval >= 300 seconds  
✔ Do not manually edit ACL entries in Linode Console

---

# 🔮 Future Roadmap

- Kyverno integration
- Admission Controller integration
- Prometheus metrics
- Grafana dashboards
- Helm chart support
- Leader-election improvements
- HA reconciler
- OpenTelemetry tracing
- GitOps examples
- Multi-cluster support

---

# 🛡️ Security Considerations

- Linode API token stored securely in Kubernetes Secret
- Minimal RBAC permissions
- Distributed locking prevents ACL corruption
- Supports secure startup gating using taints/labels

---

# 🖋️ Author

Sandip Gangdhar

GitHub: https://github.com/sandipgangdhar

---

# 📄 License

MIT License

---

# ⭐ Contributing

Contributions, feature requests, and improvements are welcome.

Please open issues or pull requests through GitHub.

---

# © 2026

LKE-E ACL Operator | Developed by Sandip Gangdhar | 2026
