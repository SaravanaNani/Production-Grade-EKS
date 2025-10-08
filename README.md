# 🏗️ Production-Grade EKS Cluster with TLS, Application Deployment, Monitoring, Storage, and Security

## 🧭 Executive Summary
This documentation provides a complete, production-grade setup for an **Amazon EKS Cluster** with:
- Automated TLS certificates using **cert-manager** and **Let’s Encrypt**
- Secure Ingress for your deployed applications
- Unified monitoring with **Prometheus**, **Grafana**, **Loki**, **Promtail**, **Node Exporter**, **cAdvisor**, and **Kube-State-Metrics**
- Persistent storage with the **AWS EBS CSI driver (gp3)** using **IRSA**
- Namespace protection and policy enforcement using **Kyverno**
- Full observability, automation, and security for real-world production use

> 💡 This guide is fully runnable and GitHub-ready — perfect for DevOps portfolios or production replication.

---

## 📚 Table of Contents
- [Architecture Overview](#architecture-overview)
- [Pre-requisites](#pre-requisites)
- [Part 1 – Base Infrastructure](#part-1--base-infrastructure)
- [Part 2 – Ingress Controller, TLS, and Application Deployment](#part-2--ingress-controller-tls-and-application-deployment)
- [Part 3 – Unified Monitoring and Storage](#part-3--unified-monitoring-and-storage)
- [Part 4 – Validation & Access](#part-4--validation--access)
- [Part 5 – Security (Kyverno)](#part-5--security-kyverno)
- [References & Linked Files](#references--linked-files)

---

## 🏗️ Architecture Overview

```
                    ┌───────────────────────────┐
                    │      Bastion Host         │
                    │  • Grafana (:3000)        │
                    │  • Loki (:3100)           │
                    └────────────┬──────────────┘
                                 │
              Logs (Promtail→Loki) + Metrics (Grafana→Prometheus)
                                 │
           ┌─────────────────────┴─────────────────────┐
           │                 Amazon EKS Cluster        │
           │  • Prometheus Operator Stack              │
           │  • Node Exporter / cAdvisor / KSM         │
           │  • Promtail DaemonSet                     │
           │  • Application Pods (adq-dev namespace)   │
           └───────────────────────────────────────────┘
```

---

## ⚙️ Pre-requisites
- AWS Account with IAM Admin access  
- Tools: `aws`, `kubectl`, `helm`, `eksctl`, `jq`  
- Registered Domain (GoDaddy or Route53)  
- Bastion host (Linux) with network access to EKS node subnets  
- Existing Base Infrastructure created (`EKS-Setup.md`)

---

## 🧱 Part 1 – Base Infrastructure
Refer to your existing file: [`EKS-Setup.md`](./EKS-Setup.md)  
> All resource names remain as: `<PROJECT_PREFIX>-dev-vpc`, `<PROJECT_PREFIX>-dev-eks`, `<PROJECT_PREFIX>-dev-sg-bastion`, etc.  
> CIDRs, routes, and Security Groups are unchanged.

---

## Step 0 — Preparation

* Project: `adq`
* Environment: `dev` | `prod`
* AWS Account: Ensure admin IAM user
* Enable billing alerts
* Create key pair: `adq-keypair-<region>` for EC2 access

---

## Step 1 — Create VPC & Subnets

### 1.1 Create VPC

* Name: `adq-dev-vpc`
* CIDR: `10.10.0.0/16`

### 1.2 Subnets

| Type    | CIDR           | AZ | Name              |
| ------- | -------------- | -- | ----------------- |
| Private | 10.10.1.0/24   | a  | adq-dev-private-a |
| Private | 10.10.2.0/24   | b  | adq-dev-private-b |
| Public  | 10.10.101.0/24 | a  | adq-dev-public-a  |
| Public  | 10.10.102.0/24 | b  | adq-dev-public-b  |

* Attach Internet Gateway: `adq-dev-igw`
* Create NAT Gateway: `adq-dev-nat` (in public-a)

### 1.3 Route Tables

| Route Table         | Default Route           | Associated Subnets                   |
| ------------------- | ----------------------- | ------------------------------------ |
| adq-dev-rtb-public  | 0.0.0.0/0 → adq-dev-igw | adq-dev-public-a, adq-dev-public-b   |
| adq-dev-rtb-private | 0.0.0.0/0 → adq-dev-nat | adq-dev-private-a, adq-dev-private-b |

**Note:** Public subnets can access the internet directly. Private subnets route through NAT for outbound access only. Use a Bastion host for secure access to private nodes.

### 1.4 Security Groups

**1.4.1 Bastion SG: `adq-dev-sg-bastion`**

* Ingress: TCP 22 → your office/public IP [0.0.0.0/0]	

* Ingress: All ICMP - IPv4 → public IP [0.0.0.0/0]	

* Ingress: TCP 3100- IPv4 → adq-dev-sg-eks-nodes	

* Ingress: TCP 9100- IPv4 → adq-dev-sg-eks-nodes	

* Ingress: TCP 3000 → your office/public IP [0.0.0.0/0]	

* Egress: HTTPS 443 → your office/public IP


**1.4.2 EKS Control Plane SG: `adq-dev-sg-eks-controlplane`**

* Ingress: 80, 443, 10250 from EKS nodes SG

**1.4.3 EKS Nodes SG: `adq-dev-sg-eks-nodes`**

* Ingress: Custom TCP 3100 → adq-dev-sg-bastionhost
* Ingress: Custom TCP 8080 → adq-dev-sg-bastionhost
* Ingress: Custom TCP 3000-32767 → public IP [0.0.0.0/0] (Optional)	

* Ingress: Custom TCP 9100 → bastionhost-pvt-IP/32
* Ingress: Custom TCP 9100 → adq-dev-sg-bastionhost


* Ingress: Custom TCP 10250 → adq-dev-sg-bastionhost
* Ingress: Custom TCP 10250 → adq-dev-sg-eks-nodes
* Ingress: TCP 22 → adq-dev-sg-bastionhost
* Ingress: HTTPS 443 → 0.0.0.0/0
* Ingress: HTTP 80 → 0.0.0.0/0


**1.4.4 DB SG: `adq-dev-sg-db`**

* Ingress: 3306 → `adq-dev-sg-eks-nodes`
  3306 → `adq-dev-sg-bastion` (optional)

---

## Step 2 — IAM Roles & EKS Cluster Setup

### 2.1 Create Worker Node Role: `adq-dev-iam-eks-nodes`

* Managed policies:

  * AmazonEKSWorkerNodePolicy
  * AmazonEC2ContainerRegistryReadOnly
  * AmazonEKS\_CNI\_Policy

### 2.2 Create Cluster Role: `adq-dev-iam-eks-cluster`

* Managed policies:

  * AmazonEKSClusterPolicy
  * AmazonEKSServicePolicy

### 2.3 Bastion Role: `adq-dev-eks-admin-role-bastion`

* Managed policies:

  * AmazonEKSClusterPolicy
  * AmazonEKSWorkerNodePolicy
  * AmazonEKS\_CNI\_Policy
  * AmazonEC2ContainerRegistryReadOnly
  * (Optional) AdministratorAccess

### 2.4 EKS Access Entry for Bastion

```bash
aws eks create-access-entry \
  --cluster-name adq-dev-eks \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/adq-dev-eks-admin-role-bastion \
  --type STANDARD

aws eks associate-access-policy \
  --cluster-name adq-dev-eks \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/adq-dev-eks-admin-role-bastion \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

### 2.5 Create EKS Cluster (Control Plane)

* Name: `adq-dev-eks`
* Kubernetes version: latest stable (1.29/1.30)
* IAM Role: `adq-dev-iam-eks-cluster`
* VPC: `adq-dev-vpc`
* Subnets: `adq-dev-private-a`, `adq-dev-private-b`
* SG: `adq-dev-sg-eks-controlplane`
* Endpoint access: Private ON, Public OFF or restricted
* Logging: Enable all

### 2.6 Create Node Group (Worker Nodes)

* Name: `adq-dev-ng`
* IAM Role: `adq-dev-iam-eks-nodes`
* Subnets: private
* Instance type: `t3.medium` (dev)
* Disk: 20 GiB
* Scaling: Min=2, Desired=2, Max=4
* SSH: Optional via Bastion only
* SG: `adq-dev-sg-eks-nodes`

---

## Step 3 — Bastion Setup

* EC2: `adq-dev-bastion`
* AMI: Amazon Linux 2
* Type: t3.micro
* Subnet: `adq-dev-public-a`
* SG: `adq-dev-sg-bastion`
* Install tools: aws-cli, kubectl, helm, git, curl
* Update kubeconfig:

```bash
aws eks update-kubeconfig --region ap-south-1 --name adq-dev-eks-cluster
kubectl get nodes
```

* Verify IAM role and metadata service with IMDSv2:

```bash
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/
curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/adq-dev-eks-admin-role-bastion
aws sts get-caller-identity
```

---

## 🔐 Part 2 – Ingress Controller, TLS, and Application Deployment

##  Application Build & Push (Example)

> **Why**: We need a containerized application image to deploy to Kubernetes.

```Dockerfile
# Use lightweight Node.js image
FROM node:18-alpine

# Working directory inside container
WORKDIR /usr/src/app

# Copy app files
COPY . .

# Install minimal dependencies
RUN npm install express

# Expose port
EXPOSE 3000

# Start app
CMD ["node", "app.js"]
```
### app.js:

```
const express = require('express');
const app = express();

app.get('/', (req, res) => {
  console.log(`[${new Date().toISOString()}] GET / request received`);
  res.send('🚀 Sample Node App for Promtail Logging Demo!');
});

setInterval(() => {
  console.log(`[${new Date().toISOString()}] App heartbeat log`);
}, 5000);

app.listen(3000, () => {
  console.log('Server running on port 3000');
});
```
## Build, tag, and push (Docker Hub example)
```bash
# login first
docker login

# build
docker build -t <dockerhub_user>/demo-node-logger:latest .

# push
docker push <dockerhub_user>/demo-node-logger:latest

```
### Install NGINX Ingress Controller
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace
kubectl get pods -n ingress-nginx
```

> 💡 Why: The NGINX ingress controller manages external traffic routing and load balancing to your Kubernetes services.

---

### Install cert-manager
```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true
kubectl get pods -n cert-manager
```

> 💡 Why: cert-manager automates TLS certificate issuance and renewal via Let’s Encrypt.

---

### ClusterIssuer (Let’s Encrypt)
✅ Replace placeholders: <YOUR_EMAIL>, <INGRESS_CLASS> (e.g., nginx)
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: <YOUR_EMAIL>
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: <INGRESS_CLASS> # for this setup nginx
```

---

### Application Deployment and Ingress
Replace <NAMESPACE>, <APP_NAME>, <DOCKERHUB_USER>, <IMAGE_TAG>, <APP_DOMAIN>, <INGRESS_CLASS>.
```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: <NAMESPACE>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <APP_NAME>
  namespace: <NAMESPACE>
spec:
  replicas: 2
  selector:
    matchLabels:
      app: <APP_NAME>
  template:
    metadata:
      labels:
        app: <APP_NAME>
    spec:
      containers:
        - name: <APP_NAME>
          image: <DOCKERHUB_USER>/<APP_NAME>:<IMAGE_TAG>
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: <APP_NAME>
  namespace: <NAMESPACE>
spec:
  type: ClusterIP
  selector:
    app: <APP_NAME>
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
      name: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <APP_NAME>
  namespace: <NAMESPACE>
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: <INGRESS_CLASS>
  tls:
    - hosts:
        - <APP_DOMAIN>
      secretName: <APP_NAME>-tls
  rules:
    - host: <APP_DOMAIN>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <APP_NAME>
                port:
                  number: 80
```
## DNS
Create a CNAME record for <APP_DOMAIN> pointing to your ingress/load balancer hostname in Godaddy or any other Domain name Provider.
Wait for DNS propagation and certificate issuance.

> ⚙️ Validation
```bash
kubectl get ingress -n adq-dev
kubectl describe certificate -n adq-dev
```

Access: `https://app.<YOUR_DOMAIN>`

---

## 📊 Part 3 – Unified Monitoring and Storage

This part covers the entire **monitoring ecosystem** (Prometheus + Grafana + Loki + Promtail) along with **persistent storage** (EBS CSI driver with IRSA and gp3 volumes).

---

### 🧩 3.1 Metrics Server Setup and Conflict Fix

```bash
kubectl get apiservice | grep metrics
kubectl delete clusterrole system:metrics-server-aggregated-reader
kubectl delete clusterrolebinding system:metrics-server
helm upgrade --install custom-metrics metrics-server/metrics-server \
  --namespace kube-system \
  --set args={--kubelet-insecure-tls}
kubectl get pods -n kube-system | grep metrics
```

> 💡 Why: The Metrics Server provides CPU and memory usage metrics for Kubernetes components and enables `kubectl top`.

---

### 🧱 3.2 Prometheus Operator Installation
```bash
kubectl create ns monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring
kubectl get pods -n monitoring
```

Access: `https://prometheus.<YOUR_DOMAIN>`

#### Custom Prometheus Stack YAML
```yaml
# <!-- prometheus-stack.yaml  -->
--
# ServiceAccount for Prometheus
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: monitoring
---
# RBAC for Prometheus
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
  - apiGroups: [""]
    resources: ["nodes", "nodes/proxy", "services", "endpoints", "pods", "namespaces", "events"]
    verbs: ["get", "list", "watch", "create", "patch"]
  - apiGroups: ["apps", "extensions"]
    resources: ["deployments", "replicasets", "daemonsets", "statefulsets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: ["monitoring.coreos.com"]
    resources: ["prometheuses","alertmanagers","servicemonitors","prometheusrules","thanosrulers","podmonitors","scrapeconfigs"]
    verbs: ["get","list","watch","create","update","patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
  - kind: ServiceAccount
    name: prometheus
    namespace: monitoring
---
# Prometheus CR (Operator will create StatefulSet)
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 1
  serviceAccountName: prometheus
  serviceMonitorSelector: {}
  podMonitorSelector: {}
  resources:
    requests:
      memory: 400Mi
      cpu: 200m
  retention: 10d
  enableAdminAPI: true
  securityContext:
    runAsUser: 65534
    runAsGroup: 65534
    fsGroup: 65534
  storage:
    volumeClaimTemplate:
      metadata:
        name: prometheus-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
        storageClassName: gp3
---
# Prometheus Service
apiVersion: v1
kind: Service
metadata:
  name: prometheus-service
  namespace: monitoring
  labels:
    app.kubernetes.io/name: prometheus
    app.kubernetes.io/instance: prometheus
spec:
  type: ClusterIP
  ports:
  - name: web
    port: 9090
    targetPort: web
  selector:
    prometheus: prometheus
---
# Ingress for Prometheus
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-ingress
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - prometheus.<Your_DOMAIN>
      secretName: prometheus-tls
  rules:
    - host: prometheus.<Your_DOMAIN>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: prometheus-service
                port:
                  number: 9090
---
# ServiceMonitor for Node Exporter
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: node-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: node-exporter
  namespaceSelector:
    matchNames:
      - monitoring
  endpoints:
  - port: metrics
    interval: 15s
---
# ServiceMonitor for Kube State Metrics
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kube-state-metrics
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: kube-state-metrics
  namespaceSelector:
    matchNames:
      - monitoring
  endpoints:
  - port: http-metrics
    interval: 15s
---
# PodMonitor for cAdvisor
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: cadvisor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: cadvisor
  namespaceSelector:
    matchNames:
      - monitoring
  podMetricsEndpoints:
  - port: http-metrics
    interval: 15s
---
# Prometheus Rules for Cluster Usage
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cluster-rules
  namespace: monitoring
spec:
  groups:
  - name: cluster.rules
    rules:
    - record: instance:node_memory_utilisation:ratio
      expr: 1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
    - record: instance:node_cpu_utilisation:rate5m
      expr: 1 - avg without (cpu) (rate(node_cpu_seconds_total{mode="idle"}[5m]))
    - record: instance:node_disk_utilisation:rate5m
      expr: rate(node_disk_io_time_seconds_total[5m])
```

> 💡 Why: Prometheus Operator simplifies managing CRDs, ServiceMonitors, and alerting rules for Kubernetes observability.

---

### 📦 3.3 Node Exporter, cAdvisor, and Kube-State-Metrics

node-exporter.yaml 

```yaml
#<!--  node-exporter.yaml HERE -->
# node-exporter.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: monitoring
  labels:
    app: node-exporter
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      hostNetwork: true
      hostPID: true
      tolerations:
        - operator: "Exists"
      containers:
        - name: node-exporter
          image: quay.io/prometheus/node-exporter:v1.8.0
          args:
            - --path.rootfs=/host
          ports:
            - name: metrics
              containerPort: 9100
              hostPort: 9100
              protocol: TCP
          volumeMounts:
            - name: rootfs
              mountPath: /host
              readOnly: true
      volumes:
        - name: rootfs
          hostPath:
            path: /

---
apiVersion: v1
kind: Service
metadata:
  name: node-exporter
  namespace: monitoring
  labels:
    app: node-exporter
spec:
  selector:
    app: node-exporter
  ports:
    - name: metrics
      port: 9100
      targetPort: 9100
  type: ClusterIP

```
cAdvisor.yaml HERE

```yaml
# <!-- cAdvisor.yaml HERE -->
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: cadvisor
  namespace: monitoring
  labels:
    app: cadvisor
spec:
  selector:
    matchLabels:
      app: cadvisor
  template:
    metadata:
      labels:
        app: cadvisor
    spec:
      containers:
        - name: cadvisor
          image: gcr.io/cadvisor/cadvisor:v0.47.2
          ports:
            - name: http-metrics   # 👈 matches PodMonitor port
              containerPort: 8080
          volumeMounts:
            - name: rootfs
              mountPath: /rootfs
              readOnly: true
            - name: var-run
              mountPath: /var/run
              readOnly: false
            - name: sys
              mountPath: /sys
              readOnly: true
            - name: docker
              mountPath: /var/lib/docker
              readOnly: true
      volumes:
        - name: rootfs
          hostPath:
            path: /
        - name: var-run
          hostPath:
            path: /var/run
        - name: sys
          hostPath:
            path: /sys
        - name: docker
          hostPath:
            path: /var/lib/docker
```

kube-state-metrics.yaml
```yaml
#<!--  kube-state-metrics.yaml HERE -->
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube-state-metrics
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kube-state-metrics
rules:
  # Core resources
  - apiGroups: [""]
    resources:
      - pods
      - services
      - endpoints
      - nodes
      - namespaces
      - replicationcontrollers
      - persistentvolumeclaims
      - persistentvolumes
      - configmaps
      - secrets
      - resourcequotas
      - limitranges
      - events
    verbs: ["list", "watch"]

  # Apps API group
  - apiGroups: ["apps"]
    resources:
      - deployments
      - daemonsets
      - replicasets
      - statefulsets
    verbs: ["list", "watch"]

  # Networking API group
  - apiGroups: ["networking.k8s.io"]
    resources:
      - networkpolicies
      - ingresses
    verbs: ["list", "watch"]

  # Policy API group
  - apiGroups: ["policy"]
    resources:
      - poddisruptionbudgets
    verbs: ["list", "watch"]

  # Storage API group
  - apiGroups: ["storage.k8s.io"]
    resources:
      - storageclasses
      - volumeattachments
    verbs: ["list", "watch"]

  # Coordination API group
  - apiGroups: ["coordination.k8s.io"]
    resources:
      - leases
    verbs: ["list", "watch"]

  # Certificates API group
  - apiGroups: ["certificates.k8s.io"]
    resources:
      - certificatesigningrequests
    verbs: ["list", "watch"]

  # Admissionregistration API group
  - apiGroups: ["admissionregistration.k8s.io"]
    resources:
      - mutatingwebhookconfigurations
      - validatingwebhookconfigurations
    verbs: ["list", "watch"]

  # Autoscaling API group
  - apiGroups: ["autoscaling"]
    resources:
      - horizontalpodautoscalers
    verbs: ["list", "watch"]

  # Batch API group
  - apiGroups: ["batch"]
    resources:
      - jobs
      - cronjobs
    verbs: ["list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-state-metrics
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kube-state-metrics
subjects:
  - kind: ServiceAccount
    name: kube-state-metrics
    namespace: monitoring
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube-state-metrics
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kube-state-metrics
  template:
    metadata:
      labels:
        app: kube-state-metrics
    spec:
      serviceAccountName: kube-state-metrics
      containers:
      - name: kube-state-metrics
        image: registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.11.0
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: kube-state-metrics
  namespace: monitoring
  labels:
    app: kube-state-metrics
spec:
  type: ClusterIP
  selector:
    app: kube-state-metrics
  ports:
    - port: 8080
      targetPort: 8080
```

> ⚙️ Validation
```bash
kubectl get pods -n monitoring
kubectl logs -n monitoring -l app=node-exporter --tail=10
```

> 💡 Why: These exporters collect essential node, container, and cluster-level metrics that power your Grafana dashboards.

---

### 🧰 3.4 Promtail DaemonSet (EKS)
```yaml
#<!--  promtail.yaml HERE -->
apiVersion: v1
kind: ServiceAccount
metadata:
  name: promtail
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: promtail
rules:
  - apiGroups: [""]
    resources:
      - pods
      - namespaces
      - nodes
    verbs:
      - get
      - list
      - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: promtail
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: promtail
subjects:
  - kind: ServiceAccount
    name: promtail
    namespace: monitoring
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: monitoring
data:
  promtail.yaml: |
    server:
      http_listen_port: 9080
      grpc_listen_port: 0
      log_level: info

    positions:
      filename: /run/promtail/positions.yaml

    clients:
      - url: http://10.10.101.140:3100/loki/api/v1/push

    scrape_configs:
      # --- System logs ---
      - job_name: varlogs
        static_configs:
          - targets: [localhost]
            labels:
              job: varlogs
              __path__: /var/log/**/*.log

      # --- Application logs ---
      - job_name: app-logs
        static_configs:
          - targets: [localhost]
            labels:
              job: app-logs
              namespace: adq-dev
              __path__: /var/log/adq-dev/*.log

      # --- Kubernetes pod logs (Static discovery for private EKS) ---
      - job_name: kubernetes-pods-static
        static_configs:
          - targets: [localhost]
            labels:
              job: kubernetes-pods
              __path__: /var/log/pods/*/*/*.log
        pipeline_stages:
          - regex:
              expression: '/var/log/pods/(?P<namespace>[^_]+)_(?P<pod>[^_]+)_[^/]+/(?P<container>[^/]+)/.*'
          - labels:
              namespace:
              pod:
              container:
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: monitoring
  labels:
    app: promtail
spec:
  selector:
    matchLabels:
      app: promtail
  template:
    metadata:
      labels:
        app: promtail
    spec:
      serviceAccountName: promtail
      tolerations:
        - operator: Exists
      containers:
        - name: promtail
          image: grafana/promtail:2.9.0
          args:
            - -config.file=/etc/promtail/promtail.yaml
          volumeMounts:
            - name: config
              mountPath: /etc/promtail
            - name: varlog
              mountPath: /var/log
              readOnly: true
            - name: positions
              mountPath: /run/promtail
      volumes:
        - name: config
          configMap:
            name: promtail-config
        - name: varlog
          hostPath:
            path: /var/log
        - name: positions
          hostPath:
            path: /run/promtail
            type: DirectoryOrCreate
```

> 💡 Why: Promtail runs on every EKS node, collecting logs from `/var/log/pods` and sending them to Loki running on Bastion.

> ⚙️ Validation

logs-validation.sh
```bash
kubectl logs -n monitoring -l app=promtail --tail=50
curl -s http://<BASTION_PVT_IP>:3100/ready
# 1) What labels exist?
curl -s "http://$BASTION_PVT_IP:3100/loki/api/v1/query" | jq .

# 2) Which jobs?
curl -s "http://$BASTION_PVT_IP:3100/loki/api/v1/query" | jq .

# 3) Streams for each job (instant)
curl -G -s "http://$BASTION_PVT_IP:3100/loki/api/v1/query" \
  --data-urlencode 'query={job="varlogs"}' | jq '.data.result | length'

curl -G -s "http://$BASTION_PVT_IP:3100/loki/api/v1/query" \
  --data-urlencode 'query={job="kubernetes-pods"}' | jq '.data.result | length'

curl -G -s "http://$BASTION_PVT_IP:3100/loki/api/v1/query" \
  --data-urlencode 'query={job="app-logs"}' | jq '.data.result | length'

# 4) Recent log lines in last 5 minutes (range); MUST use bash vars (no single-quote subshells)
START=$(($(date +%s)-300))000000000
END=$(date +%s)000000000

curl -G -s "http://$BASTION_PVT_IP:3100/loki/api/v1/query_range" \
  --data-urlencode "query={job=\"kubernetes-pods\"}" \
  --data-urlencode "limit=10" \
  --data-urlencode "start=${START}" \
  --data-urlencode "end=${END}" | jq '.data.result | length'

curl -G -s "http://$BASTION_PVT_IP:3100/loki/api/v1/query_range" \
  --data-urlencode "query={job=\"app-logs\",namespace=\"adq-dev\"}" \
  --data-urlencode "limit=10" \
  --data-urlencode "start=${START}" \
  --data-urlencode "end=${END}" | jq '.data.result | length'
```

### Extpected Outputs:
```
   {
   "status": "success",
   "data": [
     "container",
     "filename",
     "job",
     "namespace",
     "pod"
   ]
 }
 {
   "status": "success",
   "data": [
     "app-logs",
     "kubernetes-pods",
     "varlogs"
   ]
 }
 9
 5
 1
 3
 1
```

---

### 🖥️ 3.5 Loki + Grafana (on Bastion)

Loki Config: `/etc/loki/loki-config.yaml`  

```yaml
#/etc/loki/loki-config.yaml
 server:
  http_listen_port: 3100
  http_listen_address: 0.0.0.0
  log_level: info

auth_enabled: false   # disable multi-tenant auth

ingester:
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 5m
  chunk_retain_period: 30s
  wal:
    dir: /var/loki/wal

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /var/loki/index
    cache_location: /var/loki/cache
    shared_store: filesystem
  filesystem:
    directory: /var/loki/chunks

compactor:
  working_directory: /var/loki/compactor
  compaction_interval: 5m

limits_config:
  ingestion_rate_mb: 8
  ingestion_burst_size_mb: 16
  max_entries_limit_per_query: 5000
  max_streams_per_user: 10000
  reject_old_samples: true
  retention_period: 168h   # 7 days retention

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: true
  retention_period: 168h

```
Loki Installation:

```bash

#Install Loki binary (example — update to latest stable v3 release):

# check latest version at https://github.com/grafana/loki/releases, replace v3.x.y below
LOKI_VER="v3.5.5"
cd /tmp
curl -LO "https://github.com/grafana/loki/releases/download/${LOKI_VER}/loki-linux-amd64.zip"
unzip loki-linux-amd64.zip
sudo mv loki-linux-amd64 /usr/local/bin/loki
sudo chmod +x /usr/local/bin/loki
```

Loki Service: `/etc/systemd/system/loki.service`
```bash
#/etc/systemd/system/loki.service
[Unit]
Description=Loki Log Aggregator
After=network.target

[Service]
User=loki
Group=loki
Type=simple

ExecStart=/usr/local/bin/loki \
  -config.file=/etc/loki/loki-config.yaml \
  -server.http-listen-address=0.0.0.0:3100 \
  -server.grpc-listen-address=0.0.0.0:9095

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```
```
sudo systemctl daemon-reload
sudo systemctl enable --now loki
sudo systemctl status loki
```

> ⚙️ Validation - Run foreground (for tests):
```bash
/usr/local/bin/loki -config.file=/etc/loki/loki-config.yaml
```


Grafana Installation:
```bash
sudo tee /etc/yum.repos.d/grafana.repo<<EOF
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
EOF

sudo yum install -y grafana
sudo systemctl enable --now grafana-server
```

Grafana Service: `/etc/systemd/system/grafana.service`

```bash
[Unit]
Description=Grafana
After=network.target

[Service]
Type=simple
ExecStart=/usr/share/grafana/bin/grafana-server web
Restart=on-failure
User=root
WorkingDirectory=/usr/share/grafana

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl restart grafana-server
sudo systemctl status grafana-server
```

Access:
- Grafana → `https:// BASTION_PUBLIC_IP:3000` -> login with UserName and Password = admin 
- prometheus ->  `https://prometheus.<YOUR_DOMAIN>`

**Datasource Configuration**
```yaml
# Prometheus
url: https://prometheus.<YOUR_DOMAIN>
# Loki
url: http://localhost:3100
```

**Import Dashboards**
- Node Exporter: 1860  
- Kubernetes Cluster: 315  
- Loki Logs: Explore → Query `{job="app-logs", namespace="adq-dev"} |= ""`

LOKI DASHBAORD JSON: (OPTIONAL)
```json
{
  "title": "Unified EKS Logs (System + K8s + App)",
  "uid": "eks-logs-unified-v2",
  "timezone": "browser",
  "schemaVersion": 38,
  "version": 1,
  "refresh": "10s",
  "tags": ["loki","logs","kubernetes","promtail"],
  "templating": {
    "list": [
      {
        "name": "job",
        "type": "query",
        "datasource": "loki",
        "refresh": 1,
        "query": "label_values(job)",
        "includeAll": true,
        "multi": true,
        "allValue": ".+",
        "current": { "text": "All", "value": ".+" }
      },
      {
        "name": "namespace",
        "type": "query",
        "datasource": "loki",
        "refresh": 1,
        "query": "label_values({job=~\"$job\"}, namespace)",
        "includeAll": true,
        "multi": true,
        "allValue": ".+",
        "current": { "text": "All", "value": ".+" }
      },
      {
        "name": "pod",
        "type": "query",
        "datasource": "loki",
        "refresh": 1,
        "query": "label_values({job=~\"$job\", namespace=~\"$namespace\"}, pod)",
        "includeAll": true,
        "multi": true,
        "allValue": ".+",
        "current": { "text": "All", "value": ".+" }
      },
      {
        "name": "container",
        "type": "query",
        "datasource": "loki",
        "refresh": 1,
        "query": "label_values({job=~\"$job\", namespace=~\"$namespace\", pod=~\"$pod\"}, container)",
        "includeAll": true,
        "multi": true,
        "allValue": ".+",
        "current": { "text": "All", "value": ".+" }
      }
    ]
  },
  "panels": [
    {
      "type": "timeseries",
      "title": "Log volume by job",
      "datasource": "loki",
      "targets": [
        { "expr": "sum by (job) (rate({job=~\"$job\"}[1m]))", "legendFormat": "{{job}}" }
      ],
      "fieldConfig": { "defaults": { "unit": "ops" } },
      "gridPos": { "x": 0, "y": 0, "w": 12, "h": 8 }
    },
    {
      "type": "timeseries",
      "title": "Log volume by namespace",
      "datasource": "loki",
      "targets": [
        { "expr": "sum by (namespace) (rate({job=~\"$job\", namespace=~\"$namespace\"}[1m]))", "legendFormat": "{{namespace}}" }
      ],
      "fieldConfig": { "defaults": { "unit": "ops" } },
      "gridPos": { "x": 12, "y": 0, "w": 12, "h": 8 }
    },
    {
      "type": "table",
      "title": "Top pods by log lines",
      "datasource": "loki",
      "targets": [
        { "expr": "topk(10, sum by (pod) (rate({job=~\"$job\", namespace=~\"$namespace\"}[5m])))", "legendFormat": "{{pod}}" }
      ],
      "gridPos": { "x": 0, "y": 8, "w": 12, "h": 7 }
    },
    {
      "type": "table",
      "title": "Top containers by log lines",
      "datasource": "loki",
      "targets": [
        { "expr": "topk(10, sum by (container) (rate({job=~\"$job\", namespace=~\"$namespace\", pod=~\"$pod\"}[5m])))", "legendFormat": "{{container}}" }
      ],
      "gridPos": { "x": 12, "y": 8, "w": 12, "h": 7 }
    },
    {
      "type": "logs",
      "title": "Live logs",
      "datasource": "loki",
      "options": { "showLabels": true, "showTime": true, "wrapLogMessage": true },
      "targets": [
        { "expr": "{job=~\"$job\", namespace=~\"$namespace\", pod=~\"$pod\", container=~\"$container\"}" }
      ],
      "gridPos": { "x": 0, "y": 15, "w": 24, "h": 12 }
    }
  ]
}
```

> 💡 Why: Hosting Loki and Grafana externally reduces resource usage on the EKS cluster while maintaining centralized observability.

---

### 💾 3.6 AWS EBS CSI Driver with IRSA and gp3 StorageClass

#### Associate OIDC Provider
```bash
eksctl utils associate-iam-oidc-provider \
  --region us-east-1 \
  --cluster <PROJECT_PREFIX>-dev-eks \
  --approve
```

#### IAM Policy for EBS CSI Driver
```json
 {
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVolume",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:DeleteVolume",
        "ec2:ModifyVolume",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumeAttribute",
        "ec2:DescribeInstances",
        "ec2:DescribeAvailabilityZones",
        "ec2:CreateTags",
        "ec2:DescribeSnapshots",
        "ec2:CreateSnapshot",
        "ec2:DeleteSnapshot",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    }
  ]
}
```

```bash
aws iam create-policy \
  --policy-name AmazonEKS_EBS_CSI_Driver_Policy \
  --policy-document file://ebs-csi-policy.json
```

#### Create IRSA Role
```bash
eksctl create iamserviceaccount \
  --region us-east-1 \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster <PROJECT_PREFIX>-dev-eks \
  --attach-policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AmazonEKS_EBS_CSI_Driver_Policy \
  --approve \
  --role-name AmazonEKS_EBS_CSI_DriverRole
```

#### Install EBS CSI Driver via Helm
```bash
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update
helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.create=false \
  --set controller.serviceAccount.name=ebs-csi-controller-sa
kubectl get pods -n kube-system | grep ebs
```

#### gp3 StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com   # <-- Use CSI driver instead of in-tree
parameters:
  type: gp3
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

> ⚙️ Validation
```bash
kubectl get sc
kubectl get pods -n kube-system | grep ebs
```

Expected:
```
ebs-csi-controller-xxxxx   Running
ebs-csi-node-xxxxx         Running
gp3 ebs.csi.aws.com Delete WaitForFirstConsumer
```

---

### 🔄 3.7 Monitoring Flow

```
[Node Exporter / cAdvisor / KSM] → Prometheus (EKS)
        ↑
        │
 Promtail (EKS) → Loki (Bastion) → Grafana (Bastion)
```

> 💡 This unified stack provides both metrics and logs with persistent storage and secure ingress.

---

## ✅ Part 4 – Validation & Access

This section validates the entire environment — from TLS to monitoring and storage.

---

### 🧾 4.1 Certificate & TLS Validation
```bash
kubectl get certificate -A
kubectl describe certificate -n adq-dev
openssl s_client -connect app.<YOUR_DOMAIN>:443 -servername app.<YOUR_DOMAIN> </dev/null 2>/dev/null | openssl x509 -noout -issuer -subject -dates
```

> 💡 Ensure your domain resolves correctly and shows a valid Let’s Encrypt certificate.

---

### 📈 4.2 Monitoring Validation

**Prometheus Targets**
```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# open http://localhost:9090/targets
```

Check:
- Node Exporter: ✅ Up  
- cAdvisor: ✅ Up  
- Kube-State-Metrics: ✅ Up  
- Prometheus: ✅ Healthy  

---

**Grafana Dashboards**
```bash
ssh -L 3000:localhost:3000 ec2-user@<BASTION_PVT_IP>
# open http://localhost:3000
```
- Login → admin / admin (or custom credentials)
- Add DataSources: Prometheus + Loki
- Import Dashboards:
  - 1860 – Node Exporter Full
  - 315 – Kubernetes Cluster
  - 14055 – Loki Logs Overview
- Explore tab → `{namespace="adq-dev"}` → confirm app logs.

---

### 🪵 4.3 Log Validation
```bash
kubectl -n monitoring logs -l app=promtail --tail=20
curl -s http://<BASTION_PVT_IP>:3100/loki/api/v1/label/job/values | jq
```
Expected: `["kubernetes-pods","varlogs","app-logs"]`

---

### 💾 4.4 Storage Validation
```bash
kubectl apply -f pvc-test.yaml
kubectl get pvc
kubectl describe pvc <pvc-name>
```
Expected:
```
Type: gp3
Bound to volume
```

Delete test PVC:
```bash
kubectl delete pvc <pvc-name>
```

---

### 🧠 4.5 Resource Utilization
```bash
kubectl top nodes
kubectl top pods -A
```
> 💡 Confirms Metrics Server and exporters are working.

---

### 🔍 4.6 End-to-End Health Checklist

| Component | Namespace | Status | Validation Command |
|------------|------------|---------|---------------------|
| EKS Cluster | – | ✅ | `kubectl get nodes` |
| NGINX Ingress | ingress-nginx | ✅ | `kubectl get svc -n ingress-nginx` |
| cert-manager | cert-manager | ✅ | `kubectl get pods -n cert-manager` |
| Application | adq-dev | ✅ | `kubectl get pods -n adq-dev` |
| Prometheus | monitoring | ✅ | `kubectl get pods -n monitoring` |
| Node Exporter | monitoring | ✅ | `kubectl get pods -n monitoring -l app=node-exporter` |
| cAdvisor | monitoring | ✅ | `kubectl get pods -n monitoring -l app=cadvisor` |
| Promtail | monitoring | ✅ | `kubectl get pods -n monitoring -l app=promtail` |
| Loki | Bastion | ✅ | `systemctl status loki` |
| Grafana | Bastion | ✅ | `systemctl status grafana` |
| EBS CSI Driver | kube-system | ✅ | `kubectl get pods -n kube-system | grep ebs` |
| Metrics Server | kube-system | ✅ | `kubectl get pods -n kube-system | grep metrics` |
| Kyverno | kyverno | ✅ | `kubectl get pods -n kyverno` |

---

## 🛡️ Part 5 – Security (Kyverno)
Kyverno ensures safe operations by enforcing policies on namespaces and cluster resources.

Why Kyverno? Kubernetes-native policy engine using familiar YAML to validate/mutate/enforce guardrails (e.g., block dangerous operations).

---

### 🧩 5.1 Install Kyverno
```bash
helm repo add kyverno https://kyverno.github.io/kyverno
helm repo update
helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace
kubectl get pods -n kyverno
```

> 💡 Kyverno is a Kubernetes-native policy engine for validating, mutating, and generating resources.

---

### 🚫 5.2 Namespace Protection Policy

Create `protect-namespaces.yaml`:

```yaml
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
                  - "kube-public"
                  - "kube-node-lease"
                  - "monitoring"
                  - "$ADD_if_ANY_NS_Required"
```

Apply the policy:
```bash
kubectl apply -f protect-namespaces.yaml
kubectl get clusterpolicy protect-namespaces
```

---

### 🧾 5.3 Test Namespace Protection
```bash
kubectl delete namespace kube-system
```

Expected:
```
Error from server: admission webhook "validate.kyverno.svc" denied the request:
Deletion of protected namespaces is not allowed.
```

> ⚙️ To disable or update:
```bash
kubectl edit clusterpolicy protect-namespaces
# or
kubectl delete clusterpolicy protect-namespaces
```

---

## 🧩 Final Architecture Flow

```
               ┌───────────────────────────────────────────────┐
               │               Bastion / Monitoring             │
               │  • Grafana (:3000)  → visualize metrics/logs   │
               │  • Loki (:3100)     → receive logs from EKS    │
               └───────────────────────────────────────────────┘
                               ▲
                               │
                 Logs (Promtail → Loki)
                               │
       ┌───────────────────────┴────────────────────────┐
       │               Amazon EKS Cluster               │
       │  • Prometheus Stack (metrics collection)       │
       │  • Node Exporter, cAdvisor, KSM (data sources) │
       │  • Promtail (log agent)                        │
       │  • cert-manager (TLS automation)               │
       │  • EBS CSI (gp3 storage)                       │
       │  • Kyverno (security policies)                 │
       └────────────────────────────────────────────────┘
```

---

## 📘 References & Linked Files

| File | Purpose |
|------|----------|
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | Common issues and resolutions |
| [CONTRIBUTION.md](./CONTRIBUTION.md) | Contribution guide for monitoring and security |
| [INTERVIEW_QA.md](./INTERVIEW_QA.md) | EKS and DevOps interview prep |
| [WRITEUP.md](./WRITEUP.md) | Case study for portfolio presentation |
| [COMPONENTS_AND_REASONING.md](./COMPONENTS_AND_REASONING.md) | Detailed component explanations |

---

## ✅ Validation Summary

| Layer | Component | Validation |
|--------|------------|------------|
| **Networking** | Bastion ↔ EKS | `ping` or `nc -zv <BASTION_PVT_IP> 3100` |
| **TLS** | cert-manager | `kubectl describe certificate` |
| **Monitoring** | Prometheus + Grafana | `kubectl port-forward` / Grafana dashboards |
| **Logs** | Promtail + Loki | Loki `/labels` API or Grafana Explore |
| **Storage** | gp3 EBS CSI Driver | `kubectl get sc` + `kubectl describe pvc` |
| **Security** | Kyverno Policy | `kubectl delete ns kube-system` blocked |

---

## 🚀 End of Documentation

Your **Production-Grade EKS Cluster** now includes:
- Secure ingress and automated TLS
- Full observability (metrics + logs)
- Scalable gp3 persistent storage
- Cluster policy governance via Kyverno

> 💡 You can now extend this setup with CI/CD, alerting rules, and backup policies.

---

