# ⚙️ Why We Used These Components

| Component | Purpose | Why Used | Alternatives |
|------------|----------|----------|---------------|
| **Prometheus Operator** | Metrics collection | Automates CRDs, alerting rules | Plain Prometheus |
| **Loki** | Log aggregation | Label-based indexing, lightweight | ELK Stack |
| **Grafana** | Visualization | Unified view of metrics and logs | Kibana |
| **Promtail** | Log forwarding | Native Loki integration | Fluentd, Fluent Bit |
| **cAdvisor** | Container metrics | Real-time resource stats | Node Exporter only |
| **Node Exporter** | Node metrics | CPU, memory, disk usage | Telegraf |
| **Kube-State-Metrics** | K8s object metrics | Tracks deployment health | Metrics Server only |
| **Metrics Server** | HPA metrics source | Enables `kubectl top` & autoscaling | Custom metrics adapters |
| **EBS CSI Driver (gp3)** | Persistent storage | Dynamic provisioning | gp2, NFS |
| **cert-manager** | TLS management | Auto-renews HTTPS certs | Manual certs |
| **Kyverno** | Policy engine | YAML-native governance | OPA Gatekeeper |

---

## 🧩 Architecture Recap

```
[ Node Exporter | cAdvisor | Kube-State-Metrics ] --> Prometheus --> Grafana
                                        ↑
                             Promtail --> Loki
```

> 💡 All monitoring data is visualized through Grafana dashboards imported via IDs 315, 1860, and 14055.

---

## 🔗 References

- [Prometheus Docs](https://prometheus.io/docs/introduction/overview/)
- [Grafana Docs](https://grafana.com/docs/)
- [Loki Docs](https://grafana.com/docs/loki/latest/)
- [AWS EBS CSI Driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)
- [cert-manager](https://cert-manager.io/docs/)
- [Kyverno](https://kyverno.io/docs/)

---

✅ **End of Documentation Suite**
