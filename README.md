# Event Registration App — DevOps Learning Project

A Java web application deployed on AWS using a real DevOps pipeline. Built for **beginners who want to understand how DevOps works in practice** — not just theory.

Every step, every tool, and every concept is explained in plain English below.

> **What you will build:** A fully automated pipeline where pushing code to GitHub triggers Jenkins to provision AWS infrastructure with Terraform, build a Docker image, push it to ECR, and deploy it to a Kubernetes cluster on EKS — with passwords auto-generated and stored in AWS Secrets Manager, never visible to any human.

---

## What Problem Does This Project Solve?

Most tutorials show you how to manually deploy an app by SSHing into a server and running commands. That works for one person, once. In a real company:

- Multiple developers push code every day
- Servers must be created and destroyed automatically
- Passwords must never be written in code or config files
- Everything must be repeatable, automated, and auditable

This project demonstrates all of that.

---

## Concepts You Will Learn

| Concept | What it means in simple terms |
|---------|------------------------------|
| **Docker** | Package your app and everything it needs into a single portable box (container) |
| **Kubernetes (EKS)** | A system that runs and manages your containers across multiple servers |
| **Terraform** | Write code that creates AWS infrastructure (servers, networks, databases) |
| **Ansible** | Automate tasks on servers — install software, run commands, deploy apps |
| **Jenkins** | A server that watches your GitHub repo and runs your deployment automatically |
| **Trivy** | A security scanner that checks your Docker image for known vulnerabilities and your IaC configs for misconfigurations before every deployment |
| **AWS Secrets Manager** | A secure vault in AWS where passwords are stored encrypted |
| **External Secrets Operator** | A Kubernetes component that automatically pulls secrets from AWS and makes them available to your pods |
| **IRSA** | A way to give a specific Kubernetes pod permission to access AWS — without using passwords |
| **ECR** | AWS's private Docker image registry — like Docker Hub but for your own images |
| **ELB** | AWS's Load Balancer — distributes traffic to your app and gives it a public URL |

---

## Architecture Overview

This diagram shows how everything connects:

```
Developer pushes code to GitHub
        │
        │  GitHub tells Jenkins "new code is here"
        ▼
  Jenkins Pipeline (runs on an EC2 server)
        │
        ├─► Trivy (config scan)
        │       └─► Scans Terraform files, K8s manifests, Dockerfile for misconfigurations
        │
        ├─► Terraform
        │       │  Creates all AWS infrastructure:
        │       │  VPC (private network), EKS cluster (Kubernetes),
        │       │  ECR (image registry), IAM roles, Secrets Manager
        │       └─► Auto-generates DB passwords, stores in Secrets Manager
        │
        ├─► kubectl (Kubernetes CLI)
        │       └─► Connects Jenkins to the EKS cluster
        │
        ├─► Docker + Trivy (image build & scan)
        │       ├─► Builds Docker image from your Java code
        │       ├─► Trivy scans the image for CVEs — fails if CRITICAL found
        │       └─► Pushes image to ECR only after scan passes
        │
        └─► Ansible
              ├─► Installs External Secrets Operator into the cluster
              ├─► Tells ESO: "sync passwords from AWS Secrets Manager into K8s"
              ├─► Deploys MySQL database (reads passwords from K8s Secret)
              └─► Deploys Tomcat app (reads passwords from K8s Secret)
```

### How Secrets (Passwords) Flow

This is the most important concept in the project. **No human ever sets or sees the database password:**

```
Step 1: Terraform generates a random 24-character password
        │
        ▼
Step 2: Password is stored in AWS Secrets Manager (encrypted)
        │
        ▼
Step 3: External Secrets Operator reads it from AWS
        │  (ESO has permission via IRSA — a scoped IAM role)
        ▼
Step 4: ESO creates a Kubernetes Secret called "db-secret"
        │  (automatically refreshed every 1 hour)
        ▼
Step 5: MySQL pod reads password from db-secret on startup
        Tomcat pod reads password from db-secret on startup
```

---

## Tech Stack

| Layer | Technology | Why we use it |
|-------|-----------|---------------|
| Application | Java 21, Tomcat 10 | The web app that users interact with |
| Database | MySQL 8 | Stores event registrations |
| Containerisation | Docker | Packages the app so it runs the same everywhere |
| Container Registry | AWS ECR | Stores our Docker images privately in AWS |
| Orchestration | AWS EKS (Kubernetes) | Runs and manages our containers in the cloud |
| Infrastructure as Code | Terraform | Creates all AWS resources with code |
| Configuration Management | Ansible | Automates the Kubernetes deployment steps |
| CI/CD | Jenkins | Automates the pipeline end to end |
| Security Scanning | Trivy | Scans Docker images for CVEs and IaC configs for misconfigurations |
| Secrets Management | AWS Secrets Manager + ESO | Stores and syncs passwords securely |
| IAM Scoping | IRSA | Gives only the ESO pod access to Secrets Manager |
| Storage | AWS EBS gp3 | Persistent disk for MySQL data |
| Load Balancing | AWS ELB | Gives the app a public URL |

---

## Repository Layout

Every file in this repo and what it does:

```
event-registration-app/
│
├── app/                              # The Java web application
│   ├── Dockerfile                    # Instructions to build the Docker image
│   ├── pom.xml                       # Maven config — lists Java dependencies
│   └── src/main/
│       ├── java/com/eventapp/
│       │   ├── DBUtil.java           # Reads DB credentials from environment variables
│       │   ├── RegisterServlet.java  # Handles form submission, saves to MySQL
│       │   └── InitDbServlet.java    # Creates the DB table on app startup (with retry)
│       └── webapp/
│           ├── index.jsp             # The registration form (HTML + CSS)
│           ├── success.jsp           # Shown after successful registration
│           └── WEB-INF/web.xml       # Tells Tomcat which URLs map to which servlets
│
├── terraform/                        # All AWS infrastructure as code
│   ├── bootstrap/                    # Run ONCE — creates S3 bucket for Terraform state
│   │   └── main.tf
│   ├── backend.tf                    # Tells Terraform to store state in S3
│   ├── provider.tf                   # Tells Terraform which cloud (AWS) and versions
│   ├── variables.tf                  # Configurable values (region, cluster name, etc.)
│   ├── vpc.tf                        # Creates the private network (VPC + subnets)
│   ├── eks.tf                        # Creates the Kubernetes cluster on AWS
│   ├── ecr.tf                        # Creates the Docker image registry
│   ├── secrets.tf                    # Creates passwords + Secrets Manager + IAM role
│   └── outputs.tf                    # Values printed after apply (ECR URL, secret name)
│
├── ansible/                          # Automates the deployment steps
│   ├── deploy.yml                    # The main playbook — list of tasks to run
│   ├── inventory.ini                 # Tells Ansible where to run (localhost)
│   └── templates/                    # Kubernetes manifest templates
│       ├── cluster-secret-store.yml.j2   # Tells ESO to use AWS Secrets Manager
│       ├── external-secret.yml.j2        # Tells ESO which secret to sync into K8s
│       ├── mysql-statefulset.yml.j2      # Runs MySQL as a StatefulSet
│       ├── mysql-service.yml.j2          # Internal DNS name for MySQL
│       ├── deployment.yml.j2             # Runs the Tomcat app
│       ├── service.yml.j2                # Exposes the app via a public ELB
│       └── storageclass-gp3.yml.j2       # Defines EBS gp3 as the storage type
│
├── Jenkinsfile                       # The pipeline — all stages defined as code
├── docker-compose.yml                # Run the app locally without AWS
├── .env.example                      # Template for local passwords
├── .trivyignore                      # CVE IDs to suppress in Trivy scans (accepted false positives)
└── .gitignore                        # Files Git should never track (secrets, build output)
```

---

## Key Concepts Explained

### What is Docker and why do we use it?

Without Docker, deploying a Java app means installing Java, Tomcat, and all dependencies on every server — and hoping the versions match. Docker packages everything into a single image that runs identically everywhere.

Our `Dockerfile` uses a **multi-stage build**:
- **Stage 1 (build):** Uses a Maven image to compile the Java code into a WAR file
- **Stage 2 (runtime):** Copies only the WAR into a Tomcat image — no build tools in production

### What is Kubernetes and why do we use it?

Kubernetes (K8s) is a system that runs your containers and keeps them healthy. If a container crashes, K8s restarts it. If you need more capacity, K8s scales it. It also handles networking between containers.

We use AWS EKS which is Amazon's managed Kubernetes — AWS handles the control plane so we just focus on deploying our app.

**Key Kubernetes concepts used in this project:**

- **Deployment** — runs the Tomcat app. Stateless — any pod can be replaced at any time.
- **StatefulSet** — runs MySQL. Stateful — each pod has a fixed name and its own persistent storage. We use this because MySQL needs a stable disk that survives restarts.
- **Service** — gives a stable network address to a group of pods. MySQL uses a headless service (internal DNS). Tomcat uses a LoadBalancer service (public ELB).
- **Secret** — a Kubernetes object that stores sensitive data (passwords). Pods read these as environment variables.
- **Readiness Probe** — K8s checks if a pod is actually ready before sending traffic to it. We use `mysqladmin ping` to confirm MySQL is accepting connections before Tomcat tries to connect.

### What is Terraform and why do we use it?

Terraform lets you describe infrastructure as code. Instead of clicking through the AWS console to create a VPC, then an EKS cluster, then ECR — you write `.tf` files and run `terraform apply`. Terraform figures out what to create, in what order.

**Terraform state** is how Terraform remembers what it already created. We store state in an S3 bucket so the Jenkins server and any team member work from the same state. DynamoDB locking prevents two people from running `terraform apply` at the same time.

### What is IRSA and why does it matter?

IRSA stands for IAM Roles for Service Accounts. It solves a security problem:

- **Old way:** Attach an IAM policy to the EC2 node group → every pod on every node can access AWS
- **IRSA way:** Attach an IAM role to a specific Kubernetes service account → only that one pod can access AWS

In our project, only the ESO pod has permission to read from Secrets Manager. Your Tomcat pod, MySQL pod, and every other pod cannot access Secrets Manager at all — even if someone hacks into them.

### What is ESO (External Secrets Operator)?

ESO is a Kubernetes controller — a pod that runs continuously inside your cluster and watches for `ExternalSecret` resources. When it sees one, it:

1. Calls AWS Secrets Manager to get the secret value
2. Creates a Kubernetes Secret with that value
3. Refreshes it every hour automatically

This means if you rotate a password in AWS Secrets Manager, Kubernetes picks it up within an hour — no redeployment needed.

---

## Prerequisites

### What you need before starting

#### 1. AWS Account

You need an AWS account. If you don't have one, create one at [aws.amazon.com](https://aws.amazon.com). Note that this project will incur small AWS charges (~$0.15/hr while running). **Always destroy the infrastructure after testing.**

Install and configure the AWS CLI on your local machine:

```bash
# Install AWS CLI (Linux/WSL)
# This downloads the CLI installer from Amazon
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure with your AWS credentials
# You'll find your Access Key and Secret Key in AWS Console → IAM → Users → Security credentials
aws configure
# Enter: Access Key ID, Secret Access Key, Region (ap-southeast-1), Output format (json)

# Verify it works — this should print your AWS account details
aws sts get-caller-identity
```

#### 2. Jenkins Server on EC2

Jenkins is the CI/CD server that runs your pipeline. It must run on an **EC2 instance** (not your local machine) because it needs an IAM instance role to talk to AWS without storing credentials.

**Step A — Launch an EC2 instance:**
- AMI: Amazon Linux 2023
- Instance type: t3.medium
- Create a new key pair (save the .pem file — you'll need it to SSH in)
- Security group: allow inbound on port 22 (SSH) and port 8080 (Jenkins UI)

**Step B — Create and attach an IAM instance role:**

Jenkins talks to AWS (EKS, ECR, Secrets Manager, etc.) using this role — no access keys needed anywhere.

1. Go to AWS Console → IAM → Roles → Create Role
2. Trusted entity: EC2
3. Attach these policies:
   - `AmazonEKSClusterPolicy`
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonEC2ContainerRegistryFullAccess`
   - `SecretsManagerReadWrite`
   - `IAMFullAccess`
   - `AmazonVPCFullAccess`
   - `AmazonS3FullAccess`
   - `AmazonDynamoDBFullAccess`
4. Name it `jenkins-ec2-role`
5. Attach the role to your EC2 instance: EC2 Console → Select instance → Actions → Security → Modify IAM role

**Step C — SSH into the instance and install everything:**

```bash
# SSH into your EC2 instance
# Replace <YOUR-EC2-IP> with the public IP of your instance
# Replace <YOUR-KEY.pem> with the path to your key file
ssh -i <YOUR-KEY.pem> ec2-user@<YOUR-EC2-IP>
```

Once inside, run these commands one section at a time:

```bash
# ── Install Java ──────────────────────────────────────────────────────────
# Jenkins requires Java to run.
# Amazon Corretto is Amazon's supported OpenJDK distribution.
sudo dnf install -y java-21-amazon-corretto-devel

# Verify Java is installed
java -version
```

```bash
# ── Install Jenkins ───────────────────────────────────────────────────────
# Add the Jenkins repository for Amazon Linux / Red Hat
sudo wget -O /etc/yum.repos.d/jenkins.repo \
  https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key

# Install Jenkins
sudo dnf install -y jenkins

# Start Jenkins and enable it to start automatically on boot
sudo systemctl enable jenkins
sudo systemctl start jenkins

# Get the initial admin password — you'll need this to log in for the first time
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Open your browser and go to `http://<YOUR-EC2-IP>:8080`. Enter the password from above, install the suggested plugins, and create an admin user.

```bash
# ── Install Docker ────────────────────────────────────────────────────────
# Docker is used to build and push the container image.
# Amazon Linux 2023 includes Docker in its default package repo.
sudo dnf install -y docker

# Start Docker and enable it to start on boot
sudo systemctl enable docker
sudo systemctl start docker

# Allow Jenkins to run Docker without sudo.
# Without this, Jenkins will get "permission denied" when it tries to build images.
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# Verify Docker works
docker --version
```

```bash
# ── Install Ansible ───────────────────────────────────────────────────────
# Ansible runs the Kubernetes deployment tasks after the image is built.
sudo dnf install -y python3-pip

# Install system-wide (sudo) so that the jenkins user can find ansible-playbook.
# Without sudo, pip installs to ~/.local/bin which only the current user can see.
# Jenkins runs as its own user so it would get "ansible-playbook: command not found".
sudo pip3 install ansible kubernetes

# Install the Kubernetes collection for Ansible system-wide.
# -p sets the install path to a shared location all users can read.
sudo ansible-galaxy collection install kubernetes.core \
  -p /usr/share/ansible/collections

# Verify Ansible works
ansible --version
```

```bash
# ── Install kubectl ───────────────────────────────────────────────────────
# kubectl is the command-line tool for talking to your Kubernetes cluster.
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify kubectl works
kubectl version --client
```

```bash
# ── Install Helm ──────────────────────────────────────────────────────────
# Helm is a package manager for Kubernetes.
# We use it to install External Secrets Operator into the cluster.
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify Helm works
helm version --short
```

```bash
# ── Install Trivy ─────────────────────────────────────────────────────────
# Trivy is a security scanner used in the pipeline to:
#   1. Scan Terraform and Kubernetes configs for misconfigurations
#   2. Scan the Docker image for known CVEs before pushing to ECR
# The pipeline fails automatically if a CRITICAL vulnerability is found.
sudo rpm --import https://aquasecurity.github.io/trivy-repo/rpm/public.key
cat << 'EOF' | sudo tee /etc/yum.repos.d/trivy.repo
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://aquasecurity.github.io/trivy-repo/rpm/public.key
EOF
sudo dnf install -y trivy

# Verify Trivy works
trivy --version
```

```bash
# ── Install Terraform ─────────────────────────────────────────────────────
# Terraform creates all the AWS infrastructure (VPC, EKS, ECR, IAM, etc.)
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo \
  https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo dnf install -y terraform

# Verify Terraform works
terraform version
```

```bash
# ── Final verification — all tools should print their versions ────────────
java -version && docker --version && ansible --version && \
kubectl version --client && helm version --short && terraform version && trivy --version
```

#### 3. Jenkins Credentials

**None required.** This pipeline derives everything automatically:
- ECR URL — read from Terraform output after infra is provisioned
- DB passwords — auto-generated by Terraform, stored in AWS Secrets Manager
- AWS access — provided by the EC2 instance role

---

## First-Time Setup

### Step 1 — Fork and clone the repo

**Fork** means making your own copy of this repo under your GitHub account so you can push changes to it.

1. Click **Fork** at the top right of this GitHub page
2. Clone your fork to your local machine:

```bash
# Replace YOUR_GITHUB_USERNAME with your actual GitHub username
git clone https://github.com/YOUR_GITHUB_USERNAME/event-registration-app.git
cd event-registration-app
```

> The Jenkinsfile uses `checkout scm` which automatically uses whichever repo you configure in Jenkins — no hardcoded URLs to change.

### Step 2 — Set your AWS account ID in backend.tf

Terraform needs to know where to store its state. We use an S3 bucket named after your AWS account ID to make it unique.

```bash
# This command prints your AWS account ID
aws sts get-caller-identity --query Account --output text
```

Open `terraform/backend.tf` and replace `YOUR_AWS_ACCOUNT_ID` with the number printed above.

**What is backend.tf?**
Terraform keeps a record of everything it has created in a "state file". By default this is a local file on your machine — which means Jenkins can't see it. We store it in S3 so both your local machine and Jenkins work from the same state.

### Step 3 — Bootstrap the S3 state backend

This is the **only manual step** you need to run before the pipeline takes over. It creates the S3 bucket and DynamoDB table that Terraform uses to store state.

```bash
cd terraform/bootstrap

# Download the AWS provider plugin for Terraform
terraform init

# Create the S3 bucket and DynamoDB table
terraform apply -auto-approve
```

**Why can't the pipeline do this?**
Terraform needs the S3 bucket to exist before it can store state in it. It's a chicken-and-egg problem — you can't use S3 as a backend until the bucket exists, and the bucket doesn't exist until you create it. So we create it once manually with a separate bootstrap config.

**This only needs to run once ever.** Even if you destroy and redeploy the main infrastructure many times, the bootstrap resources persist.

### Step 4 — Configure the Jenkins pipeline

In Jenkins (open `http://<YOUR-EC2-IP>:8080` in your browser):

1. Click **New Item**
2. Enter a name (e.g. `event-registration-app`)
3. Select **Pipeline** and click OK
4. Under **Pipeline** section:
   - Definition: `Pipeline script from SCM`
   - SCM: `Git`
   - Repository URL: your forked repo URL (e.g. `https://github.com/YOUR_GITHUB_USERNAME/event-registration-app.git`)
   - Branch: `*/main`
   - Script Path: `Jenkinsfile`
5. Click **Save**

### Step 5 — Push your changes and run the pipeline

```bash
# Stage your changes
git add terraform/backend.tf

# Commit with a message describing what you changed
git commit -m "Configure S3 backend with my AWS account ID"

# Push to your GitHub fork
git push origin main
```

Now in Jenkins:
1. Click on your pipeline job
2. Click **Build with Parameters**
3. Select **ACTION = Deploy**
4. Click **Build**

Watch the pipeline run through each stage. The first run takes about 20-30 minutes because it provisions the entire EKS cluster from scratch. At the end, Jenkins will print the live URL of your app.

---

## Pipeline Stages Explained

### Deploy

| Stage | What it does | Why |
|-------|-------------|-----|
| **Checkout** | Downloads your code from GitHub | Jenkins needs the latest code to build and deploy |
| **Security Scan - Configs** | Trivy scans Terraform files, Kubernetes manifests, and Dockerfile for misconfigurations | Catches security issues in your infrastructure code before anything is provisioned — findings are reported but don't block the build |
| **Provision Infra** | Runs `terraform apply` — creates VPC, EKS, ECR, Secrets Manager, IAM roles | Creates all the AWS infrastructure the app needs to run |
| **Update kubeconfig** | Runs `aws eks update-kubeconfig` | Gives Jenkins's kubectl the credentials to talk to your EKS cluster |
| **Fetch Terraform outputs** | Reads ECR URL, secret name, ESO role ARN from Terraform | These values are needed by the next stages |
| **Build & Scan Image** | Builds the Docker image, runs Trivy CVE scan, then pushes to ECR | Fails the build if any CRITICAL vulnerability is found — the image is only pushed if it passes the scan |
| **Deploy via Ansible** | Installs ESO and applies all Kubernetes manifests | Deploys the pre-scanned image to EKS — no docker build here, image was already built and verified |
| **Wait & Verify** | Polls until the ELB returns HTTP 200 | Confirms the app is live before declaring success |

### Destroy

| Stage | What it does | Why |
|-------|-------------|-----|
| **Remove LoadBalancer Service** | Deletes the K8s LoadBalancer service | Must be done before destroying the cluster — otherwise AWS keeps the ELB running and you keep paying for it |
| **Destroy Infra** | Runs `terraform destroy` | Tears down all AWS resources so you stop being charged |

> **Important:** The S3 bucket and DynamoDB table (bootstrap) are NOT destroyed by this pipeline. They survive so your Terraform state is preserved between destroy/redeploy cycles.

---

## Manual Deployment (Without Jenkins)

If you want to run the deployment from your local machine instead of Jenkins:

```bash
# Step 1 — Go to the terraform directory
cd terraform

# Step 2 — Initialise Terraform (downloads providers, connects to S3 backend)
terraform init

# Step 3 — Create all AWS infrastructure
# This takes 15-20 minutes on first run
terraform apply -auto-approve

# Step 4 — Configure kubectl to talk to your new EKS cluster
aws eks update-kubeconfig --name event-app-cluster --region ap-southeast-1

# Step 5 — Read the values Terraform created
export ECR_REPO=$(terraform output -raw ecr_repo_url)
export AWS_SECRET_NAME=$(terraform output -raw db_secret_name)
export ESO_ROLE_ARN=$(terraform output -raw eso_role_arn)

# Step 6 — Run Ansible to deploy the app
cd ../ansible
ansible-playbook -i inventory.ini deploy.yml \
  -e ecr_repo_url=$ECR_REPO \
  -e build_number=manual \
  -e aws_secret_name=$AWS_SECRET_NAME \
  -e aws_region=ap-southeast-1 \
  -e eso_role_arn=$ESO_ROLE_ARN

# Step 7 — Get the app URL
# Look for EXTERNAL-IP — open that in your browser
kubectl get svc tomcat-service
```

---

## Local Development (No AWS Required)

To run the app on your local machine using Docker Compose:

```bash
# Copy the example env file and set your own passwords
cp .env.example .env
# Open .env in a text editor and change the placeholder passwords

# Start MySQL and Tomcat locally
docker compose up -d

# Open in browser
# App available at http://localhost:8081
```

---

## How to Find the DB Password

Passwords are auto-generated and stored in AWS Secrets Manager. You never need to set them, but if you need them for debugging:

```bash
# View all credentials in plain text
aws secretsmanager get-secret-value \
  --secret-id event-app/db-credentials \
  --query SecretString \
  --output text | python3 -m json.tool

# Or log into MySQL directly from inside the running pod
# mysql-0 is the name of the MySQL pod (StatefulSet pods are named with index)
kubectl exec -it mysql-0 -- bash

# Inside the pod, the password is already set as an environment variable
mysql -u root -p"$MYSQL_ROOT_PASSWORD"
```

---

## Rotating DB Credentials

Because ESO refreshes every hour, you only need to update the value in AWS Secrets Manager:

```bash
aws secretsmanager put-secret-value \
  --secret-id event-app/db-credentials \
  --secret-string '{
    "DB_URL":              "jdbc:mysql://mysql-service:3306/eventdb",
    "DB_USER":             "eventuser",
    "DB_PASS":             "your-new-app-password",
    "MYSQL_ROOT_PASSWORD": "your-new-root-password",
    "MYSQL_DATABASE":      "eventdb",
    "MYSQL_USER":          "eventuser",
    "MYSQL_PASSWORD":      "your-new-app-password"
  }'

# Force ESO to sync immediately instead of waiting up to 1 hour
kubectl annotate externalsecret db-external-secret \
  force-sync=$(date +%s) --overwrite
```

---

## Hands-On Testing

Once the app is deployed, use these exercises to verify everything works and understand key Kubernetes concepts.

---

### Exercise 1 — Register a user and check MySQL

**Step 1 — Open the app and register someone**

Get the app URL:
```bash
kubectl get svc tomcat-service
# Copy the value under EXTERNAL-IP and open http://<EXTERNAL-IP> in your browser
```

Fill in the form and submit. You should land on the success page.

**Step 2 — Log into MySQL and verify the row was saved**

```bash
# Get a shell inside the MySQL pod
# mysql-0 is the pod name — StatefulSet pods are always named <name>-0, <name>-1, etc.
kubectl exec -it mysql-0 -- bash
```

Now you are inside the MySQL container. Run:

```bash
# Log into MySQL using the root password that is already set as an env var in the pod
mysql -u root -p"$MYSQL_ROOT_PASSWORD"
```

Inside MySQL:

```sql
-- Switch to the eventdb database
USE eventdb;

-- Show all tables
SHOW TABLES;

-- View all registered users
SELECT * FROM registrations;

-- Exit MySQL
EXIT;
```

You should see the row you just submitted through the form. Type `exit` to leave the pod shell.

---

### Exercise 2 — Test PVC (Persistent Volume) — Does data survive a pod restart?

This is one of the most important Kubernetes concepts to understand. A regular container loses all its data when it restarts. A PersistentVolumeClaim (PVC) attaches an EBS volume to the pod so data survives restarts.

**What we are testing:** Kill the MySQL pod and verify your registration data is still there after it comes back.

**Step 1 — Check what data exists before killing the pod**

```bash
kubectl exec -it mysql-0 -- bash
mysql -u root -p"$MYSQL_ROOT_PASSWORD"
```
```sql
USE eventdb;
SELECT * FROM registrations;
-- Remember how many rows you see
EXIT;
```

**Step 2 — Kill the MySQL pod**

```bash
# This deletes the pod — Kubernetes will immediately create a new one
# because the StatefulSet says "always keep 1 replica running"
kubectl delete pod mysql-0
```

**Step 3 — Watch Kubernetes bring it back**

```bash
# Run this repeatedly to watch the pod restart
# You will see it go from Terminating → Pending → Running
kubectl get pods -w
# Press Ctrl+C once you see mysql-0 Running and Ready (1/1)
```

**Step 4 — Verify the data is still there**

```bash
kubectl exec -it mysql-0 -- bash
mysql -u root -p"$MYSQL_ROOT_PASSWORD"
```
```sql
USE eventdb;
SELECT * FROM registrations;
-- All your rows should still be here
EXIT;
```

**Why does the data survive?**

```
mysql-0 pod is killed
        │
        ▼
Kubernetes creates a new mysql-0 pod
        │
        ▼
K8s re-attaches the same EBS volume to the new pod
(the PVC "mysql-data-mysql-0" is bound to a specific EBS volume ID)
        │
        ▼
MySQL starts up and reads data from the EBS volume
        │
        ▼
All data is intact — exactly as it was before the pod was killed
```

The EBS volume is the key. It exists independently of the pod. The pod is temporary — the volume is permanent (until you delete the PVC).

**Step 5 — Verify the PVC and its EBS volume**

```bash
# See the PVC — notice it shows BOUND status and the storage size
kubectl get pvc

# See detailed info about the PVC including the EBS volume ID
kubectl describe pvc mysql-data-mysql-0

# You can also verify the EBS volume in AWS Console:
# EC2 → Elastic Block Store → Volumes → look for a 2Gi gp3 volume tagged with your cluster name
```

---

### Exercise 3 — Verify ESO is syncing secrets correctly

```bash
# Check the ExternalSecret status — should show READY=True and STATUS=SecretSynced
kubectl get externalsecret

# See detailed sync status including last sync time
kubectl describe externalsecret db-external-secret

# Verify the K8s Secret exists and has the correct keys
kubectl get secret db-secret
kubectl describe secret db-secret
# Note: values are base64 encoded — K8s always encodes secret values

# Decode a value to verify it matches what is in AWS Secrets Manager
kubectl get secret db-secret -o jsonpath='{.data.DB_USER}' | base64 -d
# Should print: eventuser
```

---

## Teardown

**Always destroy after testing** to avoid AWS charges.

**Via Jenkins:** Run the pipeline with **ACTION = Destroy**.

**Manually:**
```bash
# Step 1 — Delete the LoadBalancer service — releases the ELB in AWS
kubectl delete svc tomcat-service

# Step 2 — Delete all PVCs — this releases and deletes the EBS volumes in AWS
# EBS volumes are created by Kubernetes, not Terraform, so terraform destroy
# will not remove them. You must delete them manually or they keep charging you.
kubectl delete pvc --all --all-namespaces
kubectl wait --for=delete pvc --all --all-namespaces --timeout=120s

# Step 3 — Destroy all infrastructure
cd terraform && terraform destroy -auto-approve
```

To also remove the bootstrap resources (only when completely done with the project):
```bash
cd terraform/bootstrap && terraform destroy -auto-approve
```

> **Important — Stop or Terminate the Jenkins EC2 Instance**
>
> `terraform destroy` tears down the EKS cluster, ECR, VPC, and Secrets Manager — but the Jenkins EC2 instance was created manually, so Terraform does not touch it.
>
> After destroying the infrastructure, go to the **AWS Console → EC2 → Instances**, find your Jenkins server, and either:
> - **Stop** it — if you plan to use the project again soon (you won't be charged for compute, but the EBS disk still costs ~$0.10/GB/month)
> - **Terminate** it — if you are completely done (deletes the disk too, zero ongoing cost)
>
> Leaving the Jenkins EC2 instance running while the rest of the infra is destroyed wastes money with nothing to show for it.

---

## Common Errors and Fixes

| Error | What it means | How to fix |
|-------|--------------|------------|
| `permission denied on /var/run/docker.sock` | Jenkins user is not in the docker group | `sudo usermod -aG docker jenkins && sudo systemctl restart jenkins` |
| `the server has asked for the client to provide credentials` (on Jenkins) | EKS kubeconfig token expired — tokens last 15 minutes | `aws eks update-kubeconfig --name event-app-cluster --region ap-southeast-1` |
| `the server has asked for the client to provide credentials` (on local machine) | Your local IAM user is not granted access to the EKS cluster — the cluster was created by the Jenkins EC2 role so only that role has access by default | Run the access entry commands below |
| Pods stuck in `Pending` | The EBS CSI driver is not running so PVCs can't be bound to disks | `kubectl get pods -n kube-system \| grep ebs-csi` — all pods should be Running |
| ESO secret not syncing | IRSA trust policy mismatch — ESO can't assume the IAM role | Check ESO pod logs: `kubectl logs -n external-secrets deploy/external-secrets` |
| ELB DNS not resolving | DNS propagation takes time after a new ELB is created | Wait 2-3 minutes and try again |
| EBS volumes still exist after destroy | PVCs are created by Kubernetes not Terraform so `terraform destroy` doesn't remove them | Delete PVCs before destroying: `kubectl delete pvc --all --all-namespaces` |

---

### Granting Your Local Machine Access to EKS

By default, only the IAM identity that **created** the EKS cluster (the Jenkins EC2 role) can run kubectl commands against it. If you try to run kubectl from your local machine or WSL and get the credentials error, it means your local IAM user has not been granted access yet.

**Why this happens:**
```
EKS cluster is created by Jenkins EC2 role
        │
        ▼
EKS automatically grants admin access to that role only
        │
        ▼
Your local IAM user (e.g. chandu-admin) is a different identity
        └─► kubectl fails with "server asked for credentials"
```

**Fix — grant your local IAM user access to the cluster:**

```bash
# Step 1 — Get your local IAM user ARN
aws sts get-caller-identity
# Note the "Arn" value — e.g. arn:aws:iam::565968180632:user/chandu-admin

# Step 2 — Create an access entry for your IAM user
# Replace the ARN with your own from Step 1
aws eks create-access-entry \
  --cluster-name event-app-cluster \
  --principal-arn arn:aws:iam::YOUR_ACCOUNT_ID:user/YOUR_IAM_USERNAME \
  --region ap-southeast-1

# Step 3 — Grant cluster admin permissions to that entry
aws eks associate-access-policy \
  --cluster-name event-app-cluster \
  --principal-arn arn:aws:iam::YOUR_ACCOUNT_ID:user/YOUR_IAM_USERNAME \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster \
  --region ap-southeast-1

# Step 4 — Refresh your kubeconfig
aws eks update-kubeconfig --name event-app-cluster --region ap-southeast-1

# Step 5 — Verify it works
kubectl get nodes
```

This is a one-time step per IAM user. Once added, your local machine has full kubectl access to the cluster.

> **Note:** This is only needed for running kubectl locally (e.g. from your laptop or WSL). The Jenkins pipeline never needs this because it runs on the EC2 instance that created the cluster — that role already has access.

---

## Cost Estimate

| Resource | Approx. cost per hour |
|----------|----------------------|
| EKS cluster control plane | ~$0.10 |
| t3.medium SPOT node (x1) | ~$0.01-0.03 |
| ELB | ~$0.025 |
| ECR storage | negligible |
| Secrets Manager | $0.40/secret/month |
| S3 + DynamoDB (state) | negligible |

**Total while running: ~$0.15/hr. Always destroy after testing.**

---

## Key Design Decisions

**Why auto-generate passwords with Terraform instead of setting them manually?**
If a human sets a password, they can forget it, leak it in a Slack message, or reuse it. Terraform's `random_password` generates a cryptographically random 24-character password that no human ever sees. The only place it exists is in AWS Secrets Manager — encrypted.

**Why use ESO instead of fetching secrets in the pipeline?**
If Ansible fetched the password from Secrets Manager and passed it to kubectl, the password would exist in memory on the Jenkins server for a moment. ESO fetches it inside the cluster — the password never leaves AWS/Kubernetes.

**Why IRSA instead of giving the whole node group access to Secrets Manager?**
With a node-level policy, every pod on the node can call Secrets Manager — including a compromised pod. IRSA uses cryptographic identity (OIDC tokens) so only the ESO pod's service account can assume the IAM role. Every other pod is denied.

**Why StatefulSet for MySQL instead of Deployment?**
Deployments are for stateless apps — pods can be killed and replaced freely. MySQL stores data on disk. StatefulSet gives each pod a stable name (`mysql-0`) and its own persistent volume that survives restarts. Using a Deployment for a database is a common beginner mistake that causes data loss.

**Why S3 remote state instead of local state?**
Terraform state is a file that records everything Terraform has created. If it's on your laptop and Jenkins runs `terraform apply`, Jenkins has no idea what already exists and may try to create duplicates or fail entirely. S3 remote state means everyone works from the same record. DynamoDB locking prevents two runs from conflicting.
