# Event Registration App — EKS Demo Project

A Java/Tomcat event registration app deployed to Amazon EKS via a
GitHub → Jenkins → Terraform → Ansible pipeline. DB credentials are stored
in **AWS Secrets Manager** — never in Jenkins or this repo.

## Stack
Java 17, Tomcat 10, MySQL 8 (in-cluster StatefulSet), Terraform, Ansible,
Jenkins, AWS EKS / ECR / ELB / Secrets Manager.

## Repo layout
```
app/                  Java/Tomcat source, pom.xml, Dockerfile
  src/main/webapp/    index.jsp (registration form), success.jsp (confirmation)
  src/main/java/      DBUtil, RegisterServlet, InitDbServlet
terraform/            VPC, EKS, ECR, and Secrets Manager provisioning
  secrets.tf          AWS Secrets Manager secret + IAM policy for EKS nodes
ansible/              Builds & pushes Docker image, applies K8s manifests
  deploy.yml          Fetches DB credentials from AWS SM at deploy time
  templates/          Jinja2 templates for all K8s resources
Jenkinsfile           CI/CD pipeline (Deploy / Destroy)
event-registration-deployment-guide.docx  Full step-by-step deployment guide
```

## Secrets flow

DB passwords live in AWS Secrets Manager — not Jenkins:

```
terraform apply  (-var mysql_password=…)
      │
      ▼
AWS Secrets Manager  ◄── single encrypted store
      │  aws secretsmanager get-secret-value
      ▼
Ansible  ──► creates K8s Secret (db-secret)
      │
      ▼
Tomcat pod  ──► reads env vars from K8s Secret
```

## Prerequisites (one-time, on the Jenkins host)

```bash
# 1. Allow Jenkins to run Docker commands
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# 2. Ansible is installed automatically by the pipeline on first run.
#    To install manually:
pip3 install --user ansible kubernetes
ansible-galaxy collection install kubernetes.core

# 3. Set initial DB passwords as Jenkins environment variables
#    (Manage Jenkins → System → Global properties → Environment variables)
#    TF_VAR_mysql_password      = <your-app-password>
#    TF_VAR_mysql_root_password = <your-root-password>
#    Terraform uses these to seed the Secrets Manager secret on first apply.
#    After that, rotate directly in AWS SM — no re-apply needed.
```

## Jenkins credentials (only one required)

| ID | Kind | Value |
|----|------|-------|
| `ecr-repo-url` | Secret text | ECR repo URL — get it after `terraform output ecr_repo_url` |

DB passwords are no longer Jenkins credentials.

## Jenkins pipeline stages (Deploy)

| Stage | What it does |
|-------|-------------|
| Checkout | Clones main branch |
| Build WAR | `mvn clean package` |
| Provision Infra | `terraform apply` — creates VPC, EKS, ECR, Secrets Manager secret |
| Update kubeconfig | Wires `kubectl` to the new cluster |
| Fetch secret name | Reads `db_secret_name` from Terraform output |
| Install Ansible | Installs `ansible` + `kubernetes.core` via pip if not already present |
| Deploy via Ansible | Fetches secrets from AWS SM, builds/pushes image, applies K8s manifests |
| Wait & Verify | Polls until ELB returns HTTP 200, then prints the live URL |

## Quick start (manual, without Jenkins)

```bash
# 1. Build the WAR
cd app && mvn clean package

# 2. Provision infrastructure (seeds Secrets Manager)
cd ../terraform
terraform init
terraform apply \
  -var="mysql_password=<your-app-password>" \
  -var="mysql_root_password=<your-root-password>"

# 3. Wire kubectl
aws eks update-kubeconfig --name event-app-cluster --region ap-southeast-1

# 4. Export values from Terraform output
export AWS_SECRET_NAME=$(terraform output -raw db_secret_name)
export ECR_REPO=$(terraform output -raw ecr_repo_url)

# 5. Run Ansible
cd ../ansible
ansible-playbook -i inventory.ini deploy.yml \
  -e ecr_repo_url=$ECR_REPO \
  -e build_number=manual \
  -e aws_secret_name=$AWS_SECRET_NAME \
  -e aws_region=ap-southeast-1

# 6. Get the app URL
kubectl get svc tomcat-service   # open EXTERNAL-IP in a browser
```

## Rotate a DB credential

```bash
# Update the secret in AWS SM (no Terraform re-apply needed)
aws secretsmanager put-secret-value \
  --secret-id event-app/db-credentials \
  --secret-string '{"DB_URL":"jdbc:mysql://mysql-service:3306/eventdb","DB_USER":"eventuser","DB_PASS":"new-pwd","MYSQL_ROOT_PASSWORD":"new-root","MYSQL_DATABASE":"eventdb","MYSQL_USER":"eventuser","MYSQL_PASSWORD":"new-pwd"}'

# Re-run Ansible to push the new K8s Secret and restart pods
```

## Teardown (run after every session to avoid charges)

Via Jenkins — run the job with **ACTION = Destroy**.

Manually:
```bash
kubectl delete svc tomcat-service   # removes the ELB first
cd terraform && terraform destroy -auto-approve
```

## Common errors

| Error | Fix |
|-------|-----|
| `permission denied … docker.sock` | `sudo usermod -aG docker jenkins && sudo systemctl restart jenkins` |
| `ansible-playbook: command not found` | Pipeline auto-installs it; or run `pip3 install --user ansible` on the host |
| Pods stuck in `Pending` | EBS CSI driver issue — `kubectl get pods -n kube-system \| grep ebs` |
| `kubectl: no server found` | Re-run `aws eks update-kubeconfig --name event-app-cluster --region ap-southeast-1` |
| ELB DNS not resolving | Wait 2–3 min for DNS propagation after service creation |

## Further reading

See `event-registration-deployment-guide.docx` for the full architecture walkthrough,
cost estimate, AWS Secrets Manager reference, and detailed troubleshooting steps.
