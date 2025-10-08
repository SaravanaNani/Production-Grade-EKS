# 🩺 EKS Monitoring & Deployment Troubleshooting Guide

## 💡 Overview
This guide provides solutions for the most common issues encountered in the **ADQ EKS Production Stack**, including Prometheus, Loki, Grafana, TLS certificates, and EBS CSI driver.

---

## 🔧 Prometheus CRD Errors

**Issue:**
```
error: unable to recognize "prometheus-stack.yaml": no matches for kind "Prometheus" in version "monitoring.coreos.com/v1"
```

**Root Cause:**
Prometheus Operator CRDs are not installed before applying `prometheus-stack.yaml`.

**Resolution:**
```bash
kubectl create namespace monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring
```

**Validate:**
```bash
kubectl get crds | grep monitoring.coreos.com
kubectl get pods -n monitoring
```

---

## 🪵 Promtail → Loki Connection Issues

**Issue:**
Promtail logs show `context deadline exceeded` or `connection refused`.

**Root Cause:**
EKS Promtail cannot reach Loki running on Bastion.

**Resolution Steps:**
1. Verify Loki is reachable:
   ```bash
   curl -s http://<Bastion_PVT_IP>:3100/ready
   ```
2. Check Promtail logs:
   ```bash
   kubectl logs -n monitoring -l app=promtail --tail=50
   ```
3. Ensure Bastion SG allows inbound 3100 from EKS nodes.

---

## 📊 Grafana Dashboards Not Loading

**Root Cause:**
Wrong datasource name or missing Loki/Prometheus integration.

**Fix:**
1. Check datasources under **Configuration → Data Sources** in Grafana.
2. Add or verify:
   - **Prometheus**: `https://prometheus.<YOUR_DOMAIN>`
   - **Loki**: `http://localhost:3100`
3. Restart Grafana service:
   ```bash
   sudo systemctl restart grafana-server
   ```

---

## 🔒 Certificate Creation Issues (Cert-Manager)

**Issue:**
Certificate stuck in `Pending` or `Order failed`.

**Fix:**
```bash
kubectl describe certificate -n adq-dev
kubectl logs -n cert-manager deploy/cert-manager
```
Ensure `ClusterIssuer` and DNS records (CNAME) are correct.

---

## 💾 EBS CSI Mount Errors

**Error Example:**
```
Warning  FailedAttachVolume  Unable to attach or mount volumes
```

**Root Cause:**
IRSA role missing or EBS CSI driver not properly bound.

**Fix:**
Reinstall CSI driver using:
```bash
helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.create=false \
  --set controller.serviceAccount.name=ebs-csi-controller-sa
```

Validate pods:
```bash
kubectl get pods -n kube-system | grep ebs
```

---

## 🌐 Ingress DNS Issues

**Symptoms:**
App not accessible despite ingress created.

**Fix:**
- Check ingress controller logs:
  ```bash
  kubectl logs -n ingress-nginx deploy/ingress-nginx-controller
  ```
- Validate DNS record points to ALB hostname:
  ```bash
  nslookup app.<YOUR_DOMAIN>
  ```
---

✅ **End of Troubleshooting Guide**
Refer back to [`README.md`](./README.md) for complete validation flow.

