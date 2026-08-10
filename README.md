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
              ├─► Deploys External Secrets Operator (already installed by Terraform)
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
│   ├── provider.tf                   # AWS + Helm + Random providers
│   ├── variables.tf                  # Region, cluster name, instance type
│   ├── vpc.tf                        # VPC with public subnets
│   ├── eks.tf                        # EKS cluster + ESO Helm release
│   ├── ecr.tf                        # ECR container registry
│   ├── secrets.tf                    # random_password + Secrets Manager + IRSA
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

### AWS Account
- An AWS account with permissions to create VPC, EKS, ECR, IAM, and Secrets Manager resources
- AWS CLI installed and configured (`aws configure`)

### Jenkins Server (EC2)
The Jenkins server must be an EC2 instance with an **IAM instance role** that has permissions for EKS, ECR, Secrets Manager, IAM, and VPC. Jenkins connects to AWS via this role — no access keys needed.

```bash
# 1. Allow Jenkins to run Docker commands
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# 2. Install Ansible and the Kubernetes collection
pip3 install --user ansible kubernetes
ansible-galaxy collection install kubernetes.core

# 3. Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# 4. Install Terraform
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform
```

### Jenkins Credentials

Only **one** credential is required in Jenkins (Manage Jenkins → Credentials):

| ID | Kind | Value |
|----|------|-------|
| `ecr-repo-url` | Secret text | Your ECR repository URL — see Step 4 below |

No DB passwords. No AWS keys. Everything else uses the EC2 instance role.

---

## First-Time Setup (Do This Once)

### Step 1 — Clone the repo and update backend.tf

```bash
git clone https://github.com/YOUR_USERNAME/event-registration-app.git
cd event-registration-app
```

Open `terraform/backend.tf` and replace `YOUR_AWS_ACCOUNT_ID` with your actual AWS account ID:

```bash
aws sts get-caller-identity --query Account --output text
# Copy that number into terraform/backend.tf → bucket field
```

### Step 2 — Bootstrap the S3 remote state backend

This creates the S3 bucket and DynamoDB table that Terraform uses to store state. Run this once from your local machine (not Jenkins):

```bash
cd terraform/bootstrap
terraform init
terraform apply -auto-approve
```

### Step 3 — Initialise the main Terraform config

```bash
cd ..   # now in terraform/
terraform init
# Terraform will detect the S3 backend and initialise against it
```

### Step 4 — Provision infrastructure and get the ECR URL

```bash
terraform apply -auto-approve
terraform output -raw ecr_repo_url
# Copy this URL — you'll need it for the Jenkins credential
```

### Step 5 — Add the ECR URL to Jenkins

Go to **Jenkins → Manage Jenkins → Credentials → Global → Add Credential**:
- Kind: Secret text
- ID: `ecr-repo-url`
- Secret: paste the ECR URL from Step 4

### Step 6 — Push your changes and run the pipeline

```bash
git add terraform/backend.tf
git commit -m "Configure S3 backend with account ID"
git push origin main
```

Then in Jenkins: **Build with Parameters → ACTION = Deploy**.

---

## Pipeline Stages

### Deploy

| Stage | What happens |
|-------|-------------|
| **Checkout** | Clones the `main` branch from GitHub |
| **Provision Infra** | `terraform apply` — creates/updates VPC, EKS, ECR, Secrets Manager secret, IRSA role, and installs ESO via Helm |
| **Update kubeconfig** | Configures `kubectl` to point at the EKS cluster |
| **Fetch Terraform outputs** | Reads the Secrets Manager secret name from Terraform output |
| **Deploy via Ansible** | Builds & pushes Docker image; applies ESO resources, MySQL, and Tomcat to the cluster |
| **Wait & Verify** | Polls until the ELB hostname resolves and returns HTTP 200, then prints the app URL |

### Destroy

| Stage | What happens |
|-------|-------------|
| **Remove LoadBalancer Service** | Deletes the K8s service first so AWS releases the ELB (prevents orphaned resources) |
| **Destroy Infra** | `terraform destroy` — tears down all AWS resources |

> **Note:** The S3 backend and DynamoDB table (created by `terraform/bootstrap`) are NOT destroyed by the pipeline. They persist so state is preserved across destroy/redeploy cycles. Only destroy them manually when you are done with the project entirely.

---

## Manual Deployment (Without Jenkins)

If you want to deploy without Jenkins:

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

# 4. Run Ansible
cd ../ansible
ansible-playbook -i inventory.ini deploy.yml \
  -e ecr_repo_url=$ECR_REPO \
  -e build_number=manual \
  -e aws_secret_name=$AWS_SECRET_NAME \
  -e aws_region=ap-southeast-1

# 5. Get the app URL
kubectl get svc tomcat-service
# Open the EXTERNAL-IP in a browser
```

---

## Local Development

To run the app locally with Docker Compose (no AWS required):

```bash
cp .env.example .env
# Edit .env and set real passwords

docker compose up -d
# App available at http://localhost:8081
```

---

## Rotating DB Credentials

Because ESO syncs every hour, rotation only requires updating the value in AWS Secrets Manager. Kubernetes picks up the new value automatically — no redeployment needed:

```bash
# Get current secret, update password fields, put back
aws secretsmanager get-secret-value \
  --secret-id event-app/db-credentials \
  --query SecretString --output text

# Then put the updated JSON back:
aws secretsmanager put-secret-value \
  --secret-id event-app/db-credentials \
  --secret-string '{ ...updated JSON... }'

# Wait up to 1 hour for ESO to sync, or force a sync:
kubectl annotate externalsecret db-external-secret \
  force-sync=$(date +%s) --overwrite
```

---

## Teardown

**Via Jenkins:** run the pipeline with **ACTION = Destroy**.

**Manually:**
```bash
kubectl delete svc tomcat-service   # release the ELB first
cd terraform && terraform destroy -auto-approve
```

To also remove the state backend (only when you're done with the project entirely):
```bash
cd terraform/bootstrap && terraform destroy -auto-approve
```

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `permission denied on /var/run/docker.sock` | Jenkins user not in docker group | `sudo usermod -aG docker jenkins && sudo systemctl restart jenkins` |
| `kubectl: the server asked for credentials` | EKS kubeconfig token expired (15 min TTL) | `aws eks update-kubeconfig --name event-app-cluster --region ap-southeast-1` |
| Pods stuck in `Pending` | PVC can't bind — EBS CSI driver issue | `kubectl get pods -n kube-system \| grep ebs-csi` — ensure the addon is Running |
| ESO secret not syncing | IRSA trust policy mismatch | Verify the ESO service account annotation matches the IRSA role ARN in `terraform output eso_role_arn` |
| ELB DNS not resolving | DNS propagation delay | Wait 2–3 minutes after the service is created |
| `ValidationError` on IAM role description | Em-dash or non-ASCII char in description | Replace `—` with `-` in the description field |

---

## Cost Estimate

All resources use the AWS Free Tier or minimal paid tiers. Approximate cost if left running:

| Resource | Approx. cost |
|----------|-------------|
| EKS cluster control plane | ~$0.10/hr |
| t3.medium SPOT node (×1) | ~$0.01–0.03/hr |
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
