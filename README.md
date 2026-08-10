# Event Registration App — Production-Grade EKS Deployment

A Java/Tomcat web application that demonstrates a **real-world DevOps pipeline** on AWS. The project covers everything from writing the application code to deploying it on Kubernetes with automated secrets management — no passwords ever touch a CI/CD pipeline or a config file.

> **What you'll learn:** Terraform, Ansible, Jenkins, AWS EKS, ECR, Secrets Manager, External Secrets Operator, IRSA, and Docker — all wired together into a single automated pipeline.

---

## Architecture Overview

```
Developer pushes code to GitHub
        │
        ▼
  Jenkins Pipeline
        │
        ├─► Terraform ──► provisions VPC, EKS cluster, ECR repo
        │         │        generates DB passwords (random_password)
        │         └──────► stores passwords in AWS Secrets Manager
        │
        ├─► kubectl ──► configures access to the EKS cluster
        │
        └─► Ansible
              ├─► Builds Docker image → pushes to ECR
              ├─► Installs External Secrets Operator via Helm
              ├─► Creates ClusterSecretStore (ESO ↔ AWS Secrets Manager bridge)
              ├─► Creates ExternalSecret (ESO auto-creates K8s Secret from SM)
              ├─► Deploys MySQL StatefulSet (reads credentials from K8s Secret)
              └─► Deploys Tomcat app (reads credentials from K8s Secret)
```

### Secrets Flow

Passwords are **never set by a human**. Terraform generates them automatically and the External Secrets Operator syncs them into Kubernetes:

```
Terraform random_password
        │  (auto-generates 24-char password)
        ▼
AWS Secrets Manager
        │  (encrypted at rest, IAM-controlled access)
        ▼
External Secrets Operator   ◄── IRSA: scoped IAM role, ESO pod only
        │  (syncs every 1 hour)
        ▼
Kubernetes Secret (db-secret)
        │  (mounted as env vars via envFrom)
        ▼
MySQL pod  +  Tomcat pod
```

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Application | Java 17, Tomcat 10, MySQL 8 |
| Containerisation | Docker (multi-stage build) |
| Container Registry | AWS ECR |
| Orchestration | AWS EKS (Kubernetes 1.36) |
| Infrastructure as Code | Terraform |
| Configuration Management | Ansible |
| CI/CD | Jenkins |
| Secrets Management | AWS Secrets Manager + External Secrets Operator |
| IAM | IRSA (IAM Roles for Service Accounts) |
| Storage | AWS EBS gp3 (via EBS CSI driver) |
| Load Balancing | AWS ELB (provisioned automatically by K8s) |

---

## Repository Layout

```
event-registration-app/
│
├── app/                              # Java application
│   ├── Dockerfile                    # Multi-stage build (Maven → Tomcat)
│   ├── pom.xml                       # Maven dependencies
│   └── src/main/
│       ├── java/com/eventapp/
│       │   ├── DBUtil.java           # Database connection (reads env vars)
│       │   ├── RegisterServlet.java  # Handles form POST, writes to MySQL
│       │   └── InitDbServlet.java    # Creates table on startup (with retry)
│       └── webapp/
│           ├── index.jsp             # Registration form (glassmorphism UI)
│           ├── success.jsp           # Confirmation page
│           └── WEB-INF/web.xml       # Servlet descriptor
│
├── terraform/                        # AWS infrastructure
│   ├── bootstrap/                    # Run ONCE to create S3 + DynamoDB for state
│   │   └── main.tf
│   ├── backend.tf                    # S3 remote state config (fill in account ID)
│   ├── provider.tf                   # AWS + Random providers
│   ├── variables.tf                  # Region, cluster name, instance type
│   ├── vpc.tf                        # VPC with public subnets
│   ├── eks.tf                        # EKS cluster and managed node group
│   ├── ecr.tf                        # ECR container registry
│   ├── secrets.tf                    # random_password + Secrets Manager + IRSA role
│   └── outputs.tf                    # ECR URL, secret name, ESO role ARN
│
├── ansible/                          # Deployment automation
│   ├── deploy.yml                    # Main playbook
│   ├── inventory.ini                 # Localhost target
│   └── templates/                    # Kubernetes manifests (Jinja2)
│       ├── cluster-secret-store.yml.j2   # ESO → AWS SM bridge
│       ├── external-secret.yml.j2        # Tells ESO which secret to sync
│       ├── mysql-statefulset.yml.j2      # MySQL with readiness probe
│       ├── mysql-service.yml.j2          # Headless service for MySQL
│       ├── deployment.yml.j2             # Tomcat deployment
│       ├── service.yml.j2                # LoadBalancer service
│       └── storageclass-gp3.yml.j2       # EBS gp3 StorageClass
│
├── Jenkinsfile                       # Pipeline definition (Deploy / Destroy)
├── docker-compose.yml                # Local development only
├── .env.example                      # Template for local dev passwords
└── .gitignore
```

---

## Prerequisites

### 1. AWS Account
- An AWS account with permissions to create VPC, EKS, ECR, IAM, and Secrets Manager resources
- AWS CLI installed and configured on your local machine:
```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Configure with your credentials
aws configure
```

### 2. Jenkins Server (EC2)

Launch an EC2 instance (Ubuntu 22.04, t3.medium recommended) and attach an **IAM instance role** with permissions for EKS, ECR, Secrets Manager, IAM, S3, and VPC. Jenkins uses this role to talk to AWS — no access keys needed.

Then SSH into the instance and run the following:

```bash
# ── Install Java (required by Jenkins) ───────────────────────────────────
sudo apt-get update
sudo apt-get install -y fontconfig openjdk-17-jre

# ── Install Jenkins ───────────────────────────────────────────────────────
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update
sudo apt-get install -y jenkins
sudo systemctl enable jenkins && sudo systemctl start jenkins

# Get the initial admin password
sudo cat /var/lib/jenkins/secrets/initialAdminPassword

# ── Install Docker ────────────────────────────────────────────────────────
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Allow Jenkins to run Docker commands
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# ── Install Ansible ───────────────────────────────────────────────────────
sudo apt-get install -y python3-pip
pip3 install --user ansible kubernetes
ansible-galaxy collection install kubernetes.core

# ── Install kubectl ───────────────────────────────────────────────────────
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# ── Install Helm ──────────────────────────────────────────────────────────
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ── Install Terraform ─────────────────────────────────────────────────────
sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | \
  sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform

# ── Verify everything is installed ───────────────────────────────────────
java -version
jenkins --version
docker --version
ansible --version
kubectl version --client
helm version --short
terraform version
```

> Open Jenkins in your browser at `http://<EC2-PUBLIC-IP>:8080`, complete the setup wizard, and install the recommended plugins.

### 3. Jenkins Credentials

**No credentials required.** The pipeline derives everything it needs automatically:

- **ECR URL** — read from `terraform output` after infra is provisioned
- **DB passwords** — auto-generated by Terraform, stored in AWS Secrets Manager
- **AWS access** — provided by the EC2 instance role on the Jenkins server

Zero manual credential setup.

---

## First-Time Setup

### Step 1 — Fork and clone the repo

Click **Fork** on GitHub to create your own copy, then clone it:

```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/event-registration-app.git
cd event-registration-app
```

Also update the GitHub URL in `Jenkinsfile` to point to your forked repo:
```groovy
git url: 'https://github.com/YOUR_GITHUB_USERNAME/event-registration-app.git', branch: 'main'
```

### Step 2 — Set your AWS account ID in backend.tf

Get your account ID:
```bash
aws sts get-caller-identity --query Account --output text
```

Open `terraform/backend.tf` and replace `YOUR_AWS_ACCOUNT_ID` with that number.

### Step 3 — Bootstrap the S3 remote state backend

Run this **once** from your local machine. It creates the S3 bucket and DynamoDB table that Terraform uses to store state:

```bash
cd terraform/bootstrap
terraform init
terraform apply -auto-approve
```

> This is the only manual step required. The bootstrap cannot run inside the pipeline because the S3 bucket must exist before Terraform can initialise its backend.

### Step 4 — Configure the Jenkins pipeline

In Jenkins, create a new **Pipeline** job:
- Definition: Pipeline script from SCM
- SCM: Git
- Repository URL: your GitHub repo URL
- Branch: `*/main`
- Script Path: `Jenkinsfile`

### Step 5 — Push your changes and run the pipeline

```bash
git add terraform/backend.tf
git commit -m "Configure S3 backend with account ID"
git push origin main
```

Then in Jenkins: **Build with Parameters → ACTION = Deploy**.

The pipeline will provision all infrastructure, fetch the ECR URL automatically from Terraform output, and deploy the application — no manual intervention needed.

---

## Pipeline Stages

### Deploy

| Stage | What happens |
|-------|-------------|
| **Checkout** | Clones the `main` branch from GitHub |
| **Provision Infra** | `terraform apply` — creates VPC, EKS cluster, ECR repo, Secrets Manager secret, and IRSA role |
| **Update kubeconfig** | Configures `kubectl` to point at the EKS cluster |
| **Fetch Terraform outputs** | Reads the Secrets Manager secret name and ESO IAM role ARN from Terraform |
| **Deploy via Ansible** | Installs ESO via Helm, applies ESO config, deploys MySQL and Tomcat |
| **Wait & Verify** | Polls until the ELB returns HTTP 200, then prints the live app URL |

### Destroy

| Stage | What happens |
|-------|-------------|
| **Remove LoadBalancer Service** | Deletes the K8s service so AWS releases the ELB before cluster deletion |
| **Destroy Infra** | `terraform destroy` — tears down all AWS resources |

> **Note:** The S3 bucket and DynamoDB table created by `terraform/bootstrap` are **not** destroyed by the pipeline. They persist across destroy/redeploy cycles. Only destroy them manually when you are completely done with the project.

---

## Manual Deployment (Without Jenkins)

```bash
# 1. Provision infrastructure
cd terraform
terraform init
terraform apply -auto-approve

# 2. Configure kubectl
aws eks update-kubeconfig --name event-app-cluster --region ap-southeast-1

# 3. Read Terraform outputs
export ECR_REPO=$(terraform output -raw ecr_repo_url)
export AWS_SECRET_NAME=$(terraform output -raw db_secret_name)
export ESO_ROLE_ARN=$(terraform output -raw eso_role_arn)

# 4. Run Ansible
cd ../ansible
ansible-playbook -i inventory.ini deploy.yml \
  -e ecr_repo_url=$ECR_REPO \
  -e build_number=manual \
  -e aws_secret_name=$AWS_SECRET_NAME \
  -e aws_region=ap-southeast-1 \
  -e eso_role_arn=$ESO_ROLE_ARN

# 5. Get the app URL
kubectl get svc tomcat-service
# Open the EXTERNAL-IP in a browser
```

---

## Local Development

To run the app locally without AWS:

```bash
cp .env.example .env
# Edit .env and set passwords

docker compose up -d
# App available at http://localhost:8081
```

---

## Finding the DB Password

The password is auto-generated by Terraform and stored in AWS Secrets Manager. You never need to set it, but if you need it for debugging:

```bash
# View from AWS Secrets Manager (plaintext)
aws secretsmanager get-secret-value \
  --secret-id event-app/db-credentials \
  --query SecretString --output text | python3 -m json.tool

# Log into MySQL directly from inside the pod
kubectl exec -it mysql-0 -- bash
mysql -u root -p"$MYSQL_ROOT_PASSWORD"
```

---

## Rotating DB Credentials

ESO syncs every hour, so updating the secret in AWS Secrets Manager is all you need:

```bash
aws secretsmanager put-secret-value \
  --secret-id event-app/db-credentials \
  --secret-string '{
    "DB_URL":              "jdbc:mysql://mysql-service:3306/eventdb",
    "DB_USER":             "eventuser",
    "DB_PASS":             "new-app-password",
    "MYSQL_ROOT_PASSWORD": "new-root-password",
    "MYSQL_DATABASE":      "eventdb",
    "MYSQL_USER":          "eventuser",
    "MYSQL_PASSWORD":      "new-app-password"
  }'

# Force immediate sync instead of waiting up to 1 hour
kubectl annotate externalsecret db-external-secret \
  force-sync=$(date +%s) --overwrite
```

---

## Teardown

**Via Jenkins:** run the pipeline with **ACTION = Destroy**.

**Manually:**
```bash
kubectl delete svc tomcat-service        # release the ELB first
cd terraform && terraform destroy -auto-approve
```

To also remove the state backend when completely done with the project:
```bash
cd terraform/bootstrap && terraform destroy -auto-approve
```

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `permission denied on /var/run/docker.sock` | Jenkins user not in docker group | `sudo usermod -aG docker jenkins && sudo systemctl restart jenkins` |
| `kubectl: the server asked for credentials` | EKS kubeconfig token expired (15 min TTL) | `aws eks update-kubeconfig --name event-app-cluster --region ap-southeast-1` |
| Pods stuck in `Pending` | EBS CSI driver not running | `kubectl get pods -n kube-system \| grep ebs-csi` — ensure all pods are Running |
| ESO secret not syncing | IRSA trust policy mismatch | Check ESO pod logs: `kubectl logs -n external-secrets deploy/external-secrets` |
| ELB DNS not resolving | DNS propagation delay | Wait 2-3 minutes after the service is created |

---

## Cost Estimate

| Resource | Approx. cost |
|----------|-------------|
| EKS cluster control plane | ~$0.10/hr |
| t3.medium SPOT node (x1) | ~$0.01-0.03/hr |
| ELB | ~$0.025/hr |
| ECR storage | negligible |
| Secrets Manager | $0.40/secret/month |
| S3 + DynamoDB (state) | negligible |

**Always run the Destroy pipeline after testing** to avoid unexpected charges.

---

## Key Design Decisions

**Why External Secrets Operator instead of fetching secrets in Ansible?**
ESO runs inside the cluster and syncs automatically every hour. Ansible fetching secrets at deploy time means credentials are briefly in memory on the Jenkins agent. ESO keeps credentials entirely within the AWS/K8s boundary.

**Why IRSA instead of a node IAM policy?**
A node IAM policy grants every pod on that node access to Secrets Manager. IRSA uses OIDC federation to scope the permission to the ESO service account only — no other pod can read the DB credentials.

**Why `random_password` in Terraform?**
No human ever sets, sees, or rotates the password manually. Terraform owns the full lifecycle. The password is only ever stored in AWS Secrets Manager (encrypted) and in Terraform state (also encrypted in S3).

**Why SPOT instances for EKS nodes?**
Cost reduction for a demo/learning project. For production, use ON_DEMAND or a mix.
