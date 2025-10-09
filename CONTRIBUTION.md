# 🏷️ **Building a Secure Monitoring Stack on Amazon EKS — TLS, Prometheus, Grafana, Loki & Kyverno**

## 🧠 Introduction  

When I started working with Amazon EKS, I wanted to build something that reflected how production DevOps systems actually run — secure, observable, and automated.  
This project gave me hands-on experience deploying a **complete monitoring and security setup** using **Prometheus, Grafana, Loki, Promtail, cert-manager, EBS CSI Driver, and Kyverno**.  
My goal was to achieve full **cluster visibility (metrics + logs)**, **TLS automation** with Let’s Encrypt, and **namespace-level security policies** — all on EKS.  

---

## 🏗️ Architecture Diagram  

```markdown
![EKS Monitoring Architecture](./images/eks-monitoring-architecture.png)
```

This architecture connects multiple layers:  
- TLS-secured ingress for the application  
- Prometheus & Grafana for metrics  
- Loki & Promtail for logs  
- Persistent storage via EBS CSI gp3  
- Kyverno for namespace protection  

---

## ⚙️ Tools & Why Used  

| Tool | Purpose | Why Used |
|------|----------|----------|
| **Prometheus** | Collects metrics from cluster components | Core of monitoring stack |
| **Grafana** | Visualizes metrics and logs | Centralized dashboard |
| **Loki** | Log aggregation backend | Lightweight, Prometheus-style queries |
| **Promtail** | Forwards pod and node logs to Loki | DaemonSet on all nodes |
| **cert-manager** | Automates TLS/SSL certificate management | Integrates with Let’s Encrypt |
| **Kyverno** | Kubernetes policy enforcement | Protects critical namespaces |
| **AWS EBS CSI Driver** | Provides dynamic gp3 storage | Ensures data persistence for Prometheus etc. |

---

## 🔐 Part 1 — TLS + Ingress Setup  

To secure EKS workloads, I used **NGINX Ingress** with **cert-manager** for automatic TLS provisioning via Let’s Encrypt.

### ⚙️ Steps Summary  

```bash
# Install NGINX Ingress
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace

# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager   --namespace cert-manager --create-namespace   --set installCRDs=true
```

### ✉️ ClusterIssuer (Let’s Encrypt Prod)

```yaml
<!-- PLACE YOUR cluster-issuer.yaml HERE -->
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: <YOUR_EMAIL>
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
```

### 🌐 Ingress Example  

```yaml
<!-- PLACE YOUR ingress.yaml HERE -->
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: adq-app-ingress
  namespace: adq-dev
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - app.<YOUR_DOMAIN>
      secretName: app-tls
  rules:
    - host: app.<YOUR_DOMAIN>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: adq-app-service
                port:
                  number: 8080
```

### ✅ TLS Validation  

```bash
kubectl get certificate -A
openssl s_client -connect app.<YOUR_DOMAIN>:443 -servername app.<YOUR_DOMAIN> </dev/null 2>/dev/null | openssl x509 -noout -issuer -subject -dates
```

> 💡 **Why:** cert-manager automates TLS renewal — critical for production uptime.

---

## 📊 Part 2 — Monitoring Stack on EKS  

This section covers the unified monitoring setup with Prometheus, Grafana, Loki, and Promtail.

### 🧩 2.1 Metrics Server (Fix & Install)  

```bash
kubectl delete clusterrole system:metrics-server-aggregated-reader
kubectl delete clusterrolebinding system:metrics-server
helm upgrade --install metrics metrics-server/metrics-server   --namespace kube-system --set args={--kubelet-insecure-tls}
```

> 💡 Enables `kubectl top` and provides metrics to Prometheus.

---

### 🧱 2.2 Prometheus Operator  

```yaml
<!-- PLACE YOUR prometheus-stack.yaml HERE -->
```

> Installs Prometheus CRDs, ServiceMonitors, and alerting rules for EKS metrics.  
Access via `https://prometheus.<YOUR_DOMAIN>` after TLS provisioning.

---

### 📦 2.3 Node Exporter + cAdvisor + Kube-State-Metrics  

These exporters feed node, container, and cluster data into Prometheus.

```yaml
<!-- PLACE YOUR node-exporter.yaml HERE -->
<!-- PLACE YOUR cadvisor.yaml HERE -->
<!-- PLACE YOUR kube-state-metrics.yaml HERE -->
```

Validate:  
```bash
kubectl get pods -n monitoring
kubectl logs -n monitoring -l app=node-exporter --tail=10
```

---

### 🧰 2.4 Promtail → Loki → Grafana Flow  

Promtail collects EKS logs and pushes them to Loki running on the Bastion VM. Grafana queries both Prometheus and Loki as data sources.

```yaml
<!-- PLACE YOUR promtail.yaml HERE -->
```

Loki runs on the Bastion host with its own systemd service and `/etc/loki/loki-config.yaml`.  
Grafana accesses both Loki and Prometheus for dashboards and log queries.

> 💡 **Tip:** Separate Grafana + Loki on Bastion to reduce EKS resource load.

---

## 💾 Part 3 — Persistent Storage with EBS CSI Driver (gp3)  

Monitoring components like Prometheus require durable storage.  

```yaml
<!-- PLACE YOUR storageclass.yaml HERE -->
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

Validate:  
```bash
kubectl get sc
kubectl get pods -n kube-system | grep ebs
```

> 💡 The EBS CSI Driver uses IRSA for permissions and ensures persistent gp3 volumes for Prometheus data.

---

## 🛡️ Part 4 — Security with Kyverno  

Kyverno adds policy-based governance to Kubernetes.

```yaml
<!-- PLACE YOUR protect-namespaces.yaml HERE -->
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: protect-namespaces
spec:
  validationFailureAction: Enforce
  rules:
    - name: prevent-deleting-namespaces
      match:
        resources:
          kinds:
            - Namespace
      validate:
        message: "Deletion of protected namespaces is not allowed."
        deny:
          conditions:
            all:
              - key: "{{request.operation}}"
                operator: Equals
                value: "DELETE"
              - key: "{{ request.name || request.object.metadata.name }}"
                operator: In
                value:
                  - "default"
                  - "kube-system"
                  - "monitoring"
                  - "adq-dev"
```

Test:  
```bash
kubectl delete namespace monitoring
# ❌ Denied by Kyverno webhook
```

> 💡 Prevents accidental deletion of critical namespaces.

---

## 🧪 Part 5 — Validation & Troubleshooting  

```bash
kubectl get pods -A
kubectl get ingress -A
kubectl get certificate -A
kubectl top nodes
kubectl top pods -A
```

Common fix I faced:  
`metrics-server` role conflict — resolved by deleting default roles and reinstalling with `--kubelet-insecure-tls`.

> 💡 Regularly check Prometheus targets and Grafana datasources after any Helm upgrade.

---

## 🚀 Results & Learnings  

By completing this setup, I achieved:  
- ✅ End-to-end TLS secured EKS cluster  
- ✅ Unified metrics and logging visibility  
- ✅ Persistent storage for Prometheus and Grafana  
- ✅ Namespace-level governance with Kyverno  

### 🧠 Key Takeaways  
- Automating TLS with cert-manager simplifies renewals and increases security.  
- Prometheus and Loki together provide a complete view of application and node health.  
- Persistent gp3 storage is essential for production grade monitoring.  
- Kyverno adds a simple YAML-based policy layer for cluster safety.  

---

## 🧩 Final Architecture Flow  

```
               ┌───────────────────────────────────────────────┐
               │               Bastion / Monitoring             │
               │  • Grafana (:3000) → Metrics & Logs View      │
               │  • Loki (:3100)     → Log Aggregation         │
               └───────────────────────────────────────────────┘
                               ▲
                               │
                 Logs (Promtail → Loki)
                               │
       ┌───────────────────────┴────────────────────────┐
       │               Amazon EKS Cluster               │
       │ • Prometheus Operator    (metrics)             │
       │ • Node Exporter, cAdvisor, KSM                │
       │ • cert-manager (TLS)                          │
       │ • EBS CSI (gp3 storage)                       │
       │ • Kyverno (Security Policies)                 │
       └────────────────────────────────────────────────┘
```

---

## 🧾 Blog Preview (for LinkedIn / Notion Summary)

> 🚀 **End-to-End Monitoring & Security on Amazon EKS**  
> I recently completed a full EKS setup integrating Prometheus, Grafana, Loki, and Kyverno with automated TLS via cert-manager.  
> This project helped me understand how production-grade DevOps systems achieve observability, persistence, and security — from NGINX ingress with Let’s Encrypt to namespace protection with Kyverno.  
>  
> 🔹 Stack: EKS • Prometheus • Grafana • Loki • Promtail • Kyverno • EBS CSI (gp3) • cert-manager  
>  
> 💡 Built, validated, and secured — end to end.
