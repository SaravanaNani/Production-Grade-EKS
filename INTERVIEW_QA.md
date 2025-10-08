# 🧠 EKS Monitoring & TLS Interview Preparation

## 📋 General Cluster Questions
1. **What is Amazon EKS?**  
   EKS is a managed Kubernetes service by AWS that simplifies cluster management using AWS infrastructure.

2. **Why use IRSA (IAM Role for Service Account)?**  
   It allows fine-grained IAM permissions for pods, avoiding over-privileged node roles.

3. **What is gp3 and why use it?**  
   gp3 is the latest EBS volume type, offering better IOPS and throughput at lower cost than gp2.

---

## 🔐 TLS & cert-manager
4. **What is cert-manager?**  
   A Kubernetes controller that automates TLS certificate issuance and renewal using ACME (Let’s Encrypt).

5. **Why use Let’s Encrypt with ClusterIssuer?**  
   Enables automatic HTTPS for all ingress resources across namespaces.

6. **How do you verify a TLS certificate in Kubernetes?**  
   ```bash
   kubectl describe certificate -A | grep -i "status"
   ```

---

## 📊 Monitoring Stack
7. **Why Prometheus Operator instead of standalone Prometheus?**  
   Operator simplifies configuration, automatically manages CRDs, and integrates ServiceMonitors.

8. **What are ServiceMonitors and PodMonitors?**  
   Custom resources used by Prometheus Operator to discover metrics from services and pods.

9. **Difference between Promtail and Fluentd?**  
   Promtail is lightweight, designed for Loki; Fluentd supports broader log shipping but heavier.

10. **Why Loki over ELK Stack?**  
    Loki stores logs by labels instead of full-text indexing, making it more cost-efficient.

---

## 🧰 Storage & IRSA
11. **What does IRSA do for the EBS CSI driver?**  
    Assigns specific IAM permissions to CSI pods to manage EBS volumes securely.

12. **How to verify EBS CSI driver pods?**  
    ```bash
    kubectl get pods -n kube-system | grep ebs
    ```

13. **What’s in a gp3 StorageClass YAML?**  
    ```yaml
    provisioner: ebs.csi.aws.com
    parameters:
      type: gp3
    ```

---

## 🧱 Security & Kyverno
14. **What does Kyverno do?**  
    Enforces Kubernetes policies natively using YAML instead of complex Rego.

15. **Example of a Kyverno rule?**  
    Prevent deletion of critical namespaces:
    ```yaml
    match:
      resources:
        kinds: ["Namespace"]
    validate:
      message: "Deletion not allowed."
    ```

---

## 💡 Advanced Scenarios
16. **How can you monitor cAdvisor metrics?**  
    Using a PodMonitor in `prometheus-stack.yaml` to scrape `:8080/metrics`.

17. **How do Prometheus and Grafana communicate securely?**  
    Via HTTPS endpoints secured with cert-manager-generated TLS secrets.

18. **What are Loki labels and why important?**  
    They categorize logs (namespace, job, pod) for efficient queries via LogQL.

19. **How to check active Prometheus targets?**  
    ```bash
    kubectl port-forward svc/prometheus-service 9090:9090 -n monitoring
    # open http://localhost:9090/targets
    ```

20. **What’s the retention period in Loki?**  
    Configurable in `loki-config.yaml` (default: 7 days).

---

✅ For deeper insights, see [`COMPONENTS_AND_REASONING.md`](./COMPONENTS_AND_REASONING.md).
