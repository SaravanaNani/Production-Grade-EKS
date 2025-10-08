# 🤝 Contribution Guidelines for Monitoring & EKS Project

## 📘 Overview
Thank you for contributing to the **ADQ EKS Production Stack** project.  
This document outlines the process for contributing new monitoring components, YAML manifests, and documentation.

---

## 🪜 Workflow

1. **Fork** the repository.
2. **Clone** your fork:
   ```bash
   git clone https://github.com/<your-username>/ADQ-EKS-Setup-Docs.git
   ```
3. **Create a new branch:**
   ```bash
   git checkout -b feature/<feature-name>
   ```

4. Add or update configuration files. Use placeholders like:
   ```yaml
   <!-- PLACE YOUR prometheus-stack.yaml HERE -->
   <!-- PLACE YOUR promtail.yaml HERE -->
   <!-- PLACE YOUR node-exporter.yaml HERE -->
   ```

5. **Test all YAMLs** using:
   ```bash
   kubectl apply --dry-run=client -f <file>.yaml
   ```

6. **Commit convention:**
   ```
   feat: add new Prometheus ServiceMonitor for node-exporter
   fix: correct Loki datasource URL in Grafana config
   docs: improve EBS CSI driver setup instructions
   ```

7. **Push changes** and submit a Pull Request (PR):
   ```bash
   git push origin feature/<feature-name>
   ```

---

## 🧩 Branch Naming Conventions

| Type | Example | Description |
|------|----------|-------------|
| `feature/` | `feature/promtail-daemonset` | New feature or YAML |
| `fix/` | `fix/csi-driver-role` | Bug or configuration fix |
| `docs/` | `docs/update-monitoring-section` | Documentation changes |

---

## 🧠 Contribution Credits

- **Infrastructure & Monitoring Design:** Saravana L  
- **Documentation Architecture:** ChatGPT (OpenAI)  
- **Open Source Tools:** Prometheus, Grafana, Loki, EKS, cert-manager  

---
