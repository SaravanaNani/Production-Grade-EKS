# Production-Grade-EKS
# Production-Grade EKS Cluster with TLS, Monitoring, Storage, and Security

A complete, production-ready Amazon EKS setup with automated TLS, robust monitoring (Prometheus, Loki, Grafana, Promtail), gp3 storage via the AWS EBS CSI driver, and security hardening with Kyverno — formatted for GitHub and ready for portfolio use.

> 💡 **Goal:** Provide a single source of truth for provisioning, securing, operating, and observing an EKS cluster end-to-end.

---

## Table of Contents

- [Executive Summary](#executive-summary)
- [Architecture Overview](#architecture-overview)
- [Pre-requisites](#pre-requisites)
- [Part 1 – Base Infrastructure Setup (unchanged)](#part-1--base-infrastructure-setup-unchanged)
- [Part 2 – TLS & Application Deployment](#part-2--tls--application-deployment)
- [Part 3 – Monitoring Stack (Prometheus, Loki, Grafana, Promtail)](#part-3--monitoring-stack-prometheus-loki-grafana-promtail)
- [Part 4 – Storage & CSI Driver (gp3)](#part-4--storage--csi-driver-gp3)
- [Part 5 – Namespace Protection & Hardening (Kyverno)](#part-5--namespace-protection--hardening-kyverno)
- [Part 6 – Validation & Access](#part-6--validation--access)
- [Why These Components](#why-these-components)
- [Troubleshooting](#troubleshooting)
- [Related Files](#related-files)

---

## Executive Summary

This project provisions a production-grade EKS cluster and adds:
- Automated HTTPS certificates with **cert-manager** and **Let’s Encrypt**
- **App deployment** via Kubernetes Deployment/Service/Ingress
- **Observability** with **kube-prometheus-stack** (Prometheus + Alertmanager + Grafana), **Loki** (logs), and **Promtail**
- **Persistent storage** through **AWS EBS CSI Driver** with a **gp3** StorageClass
- **Security hardening** using **Kyverno** (namespace protection and policy enforcement)

All infra names, CIDRs, and security group rules are preserved exactly as defined in your base `EKS-Setup.md`.

---

## Architecture Overview

```
[End Users]
    │
    ▼
[Public DNS (GoDaddy/Route53)]  ──►  [ALB/NLB]  ──►  [Ingress Controller (nginx)]
                                               │
                                               ├──►  [cert-manager (ACME/HTTP-01)]
                                               ▼
                                         [Kubernetes Services]
                                               │
                                               ▼
                                            [Pods]
                                               │
                              ┌──────── Metrics ────────┐
                              ▼                        ▼
                        [Prometheus Operator]     [Promtail]
                              │                        │
                              ▼                        ▼
                        [Prometheus + Alertmanager]  [Loki]
                              │                        │
                              └──────────►  [Grafana Dashboards]  ◄───────────┘

[Storage]  EBS CSI Driver  →  gp3 StorageClass  →  PVC/PV
[Security] Kyverno policies (incl. namespace deletion protection)
```

---

## Pre-requisites

- AWS account with admin access (or equivalent to create EKS, IAM, VPC, ALB/NLB, IAM roles)
- CLI tools installed: `aws`, `kubectl`, `helm`, `eksctl` (or Terraform if applicable)
- A domain managed in **GoDaddy** (or any DNS) to point `A/CNAME` to your ingress/load balancer
- Docker access to build & push images to a registry (e.g., Docker Hub)
- Your existing **base infrastructure** Markdown: `EKS-Setup.md`

> ⚠️ **Do not modify** any names, CIDRs, or security group rules defined in the base infra. We will insert that content verbatim.

---

## Part 1 – Base Infrastructure Setup (unchanged)

> ✅ This section **must remain exactly as-is** from your `EKS-Setup.md` (including resource names like `<PROJECT_PREFIX>-dev-vpc`, `<PROJECT_PREFIX>-dev-sg-bastion`, `<PROJECT_PREFIX>-dev-eks`, all CIDRs, routes, and SG rules).

<!-- BEGIN: BASE INFRA (VERBATIM FROM EKS-Setup.md). DO NOT EDIT ANYTHING INSIDE THESE TAGS. -->
<!-- PASTE THE FULL CONTENT OF YOUR EKS-Setup.md BELOW. NO CHANGES, NO REFORMATTING. -->
<!-- END: BASE INFRA -->

---

## Part 2 – TLS & Application Deployment

### Why TLS and cert-manager
> 💡 **Why TLS?** Encrypts traffic end-to-end, enables trust (HTTPS), and is mandatory for many security/compliance needs.  
> 💡 **Why cert-manager?** Automates issuance & renewal of certificates from Let’s Encrypt using ACME challenges (HTTP-01/DNS-01), removing manual toil.

### Step 1: Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
helm install cert-manager jetstack/cert-manager   --namespace cert-manager   --set installCRDs=true
kubectl -n cert-manager get pods
```

### Step 2: Create ClusterIssuer (Let’s Encrypt — HTTP-01)

> ✅ Replace placeholders: `<YOUR_EMAIL>`, `<INGRESS_CLASS>` (e.g., `nginx`)

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
            class: <INGRESS_CLASS>
```

### Step 3: Deploy your Application (Deployment, Service, Ingress)

> Replace `<NAMESPACE>`, `<APP_NAME>`, `<DOCKERHUB_USER>`, `<IMAGE_TAG>`, `<APP_DOMAIN>`, `<INGRESS_CLASS>`.

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

### DNS

- Create a **CNAME** record for `<APP_DOMAIN>` pointing to your ingress/load balancer hostname.
- Wait for DNS propagation and certificate issuance (`kubectl describe certificate -n <NAMESPACE> <APP_NAME>-tls`).

---

## Part 3 – Monitoring Stack (Prometheus, Loki, Grafana, Promtail)

> 💡 **Why Prometheus Operator (kube-prometheus-stack)?** Bundles CRDs, Prometheus, Alertmanager, and Grafana for a cohesive, Kubernetes-native monitoring setup.  
> 💡 **Why Loki + Promtail?** Cost-efficient, label-based log aggregation tightly integrated with Grafana.

### Install kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring
kubectl -n monitoring get pods
```

### Install Loki and Promtail

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Loki (single binary or distributed — choose one)
helm install loki grafana/loki -n monitoring

# Promtail
helm install promtail grafana/promtail -n monitoring   --set "config.clients[0].url=http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
```

### Access Grafana

- Get the admin password:
  ```bash
  kubectl get secret -n monitoring monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 -d; echo
  ```
- Port forward:
  ```bash
  kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
  ```
- Add Loki as a data source (URL: `http://loki.monitoring.svc.cluster.local:3100`) and import Kubernetes dashboards.

---

## Part 4 – Storage & CSI Driver (gp3)

> 💡 **Why IRSA?** Grants fine-grained, least-privilege IAM permissions to Kubernetes service accounts without node-wide credentials.

### Option A (Recommended): AWS-managed Addon with IRSA

```bash
# Create/add the AmazonEBSCSIDriverPolicy to an IAM role trusted by your cluster OIDC
eksctl create iamserviceaccount   --name ebs-csi-controller-sa   --namespace kube-system   --cluster <EKS_CLUSTER_NAME>   --role-name <ROLE_NAME>   --attach-policy-arn arn:aws:iam::<AWS_ACCOUNT_ID>::aws:policy/service-role/AmazonEBSCSIDriverPolicy   --approve
aws eks create-addon --cluster-name <EKS_CLUSTER_NAME> --addon-name aws-ebs-csi-driver
```

### Option B: Helm install with pre-created IRSA role

```bash
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update
helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver   --namespace kube-system   --set controller.serviceAccount.create=false   --set controller.serviceAccount.name=ebs-csi-controller-sa   --set enableVolumeResizing=true   --set enableVolumeSnapshot=true
```

### Create gp3 StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

---

## Part 5 – Namespace Protection & Hardening (Kyverno)

> 💡 **Why Kyverno?** Kubernetes-native policy engine using familiar YAML to validate/mutate/enforce guardrails (e.g., block dangerous operations).

### Install Kyverno

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno -n kyverno --create-namespace
kubectl -n kyverno get pods
```

### Policy: Block Namespace Deletion (example)

> Replace placeholders with namespaces you want protected.

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: protect-namespaces
spec:
  validationFailureAction: enforce
  background: false
  rules:
    - name: block-namespace-deletion
      match:
        any:
          - resources:
              kinds:
                - Namespace
      preconditions:
        all:
          - key: "{{ request.operation }}"
            operator: Equals
            value: DELETE
      validate:
        message: "Deletion of protected namespaces is blocked by policy."
        deny:
          conditions:
            any:
              - key: "{{ request.object.metadata.name }}"
                operator: In
                value:
                  - kube-system
                  - default
                  - monitoring
                  - <ADD_MORE_NAMESPACES>
```

---

## Part 6 – Validation & Access

- Verify nodes and core components:
  ```bash
  kubectl get nodes -o wide
  kubectl get pods -A
  ```
- Check ingress:
  ```bash
  kubectl get ingress -A
  ```
- Describe certificate and ensure it’s **Ready**:
  ```bash
  kubectl describe certificate -n <NAMESPACE> <APP_NAME>-tls
  ```
- Storage test:
  ```bash
  kubectl apply -f https://k8s.io/examples/pods/storage/pv-claim.yaml
  kubectl get pvc,pv
  ```

---

## Why These Components

See detailed reasoning in [COMPONENTS_AND_REASONING.md](./COMPONENTS_AND_REASONING.md).

---

## Troubleshooting

For real-world issues and fixes (CRDs, IRSA, ingress, cert-manager, DNS, Promtail, storage), see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).

---

## Related Files

- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
- [INTERVIEW_QA.md](./INTERVIEW_QA.md)
- [CONTRIBUTION.md](./CONTRIBUTION.md)
- [WRITEUP.md](./WRITEUP.md)
- [COMPONENTS_AND_REASONING.md](./COMPONENTS_AND_REASONING.md)
