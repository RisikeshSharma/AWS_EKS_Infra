# AWS EKS Infrastructure with GitHub Actions CI/CD

Repository: [https://github.com/RisikeshSharma/AWS_EKS_Infra.git](https://github.com/RisikeshSharma/AWS_EKS_Infra.git)

This repository contains the production-ready Terraform code to provision an AWS EKS Cluster (`v1.30`) with a Managed Node Group of **2 Worker Nodes**, completely integrated with a **GitHub Actions CI/CD Pipeline**.

---

## ⚙️ CI/CD Features (.github/workflows/deploy.yml)

- **Push to Main**: Automatically plans and applies infrastructure changes.
- **Manual Trigger (`workflow_dispatch`)**: One-click **Apply**, **Plan**, or **Destroy** directly from GitHub UI!

---

## 🔑 Required GitHub Secrets

Add these secrets in GitHub Repo **Settings ➔ Secrets and variables ➔ Actions**:

1. `AWS_ACCESS_KEY_ID`
2. `AWS_SECRET_ACCESS_KEY`
3. `AWS_REGION` (e.g. `us-east-1`)

---

## 🚀 Push Code to GitHub

```bash
git init
git remote add origin https://github.com/RisikeshSharma/AWS_EKS_Infra.git
git branch -M main
git add .
git commit -m "Setup Terraform AWS EKS Infrastructure and GitHub Actions CI/CD"
git push -u origin main
```
