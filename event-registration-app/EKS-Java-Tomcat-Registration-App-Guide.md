# Hands-On Project: Event Registration App on EKS
### Java + Tomcat + MySQL | Terraform + Ansible + Jenkins + GitHub + AWS

---

## 1. Project Summary

A simple event-registration web app (name, email, contact, address form → stored in MySQL), containerized and deployed to a low-cost EKS cluster, with a fully automated pipeline:

```
GitHub (code) → Jenkins (pull, build, push) → Terraform (infra) → Ansible (deploy to EKS) → ELB (public access)
```

This mirrors a real production pattern at minimal scale, so every tool you specified is used exactly as it would be in a job.

---

## 2. Adjustments Made (and why)

| Your spec | Adjustment | Reason |
|---|---|---|
| MySQL | Run as a Kubernetes **StatefulSet** with an EBS-backed PVC inside the same EKS cluster (not RDS) | Keeps everything inside the cluster you're already paying for — no extra RDS bill. I note the RDS alternative below for when you want to demonstrate managed-DB patterns too. |
| Ansible "deploying Tomcat into containers" | Ansible doesn't configure containers directly — it (a) builds & pushes the Docker image, and (b) templates/applies the Kubernetes manifests using the `kubernetes.core.k8s` module | This keeps Ansible's real job (config/orchestration) while still using containers + K8s as the runtime, which is the industry-standard combo |
| No domain | Kubernetes `Service type: LoadBalancer` → auto-provisions a Classic/NLB ELB with a public DNS name | Simplest way to get a public endpoint without Ingress controller complexity |
| Minimum cost | Single managed node group, 1–2 `t3.small`/`t3.medium` nodes, single-AZ, gp3 volumes, **destroy after each session** | EKS control plane is a fixed $0.10/hr regardless of nodes — the biggest lever you control is node count/size and *not leaving it running* |

---

## 3. Architecture

```
                        ┌─────────────────────────────┐
                        │           GitHub             │
                        │  (app code, Dockerfile,      │
                        │   Terraform, Ansible, k8s)   │
                        └───────────────┬───────────────┘
                                        │ webhook / poll
                                        ▼
                        ┌─────────────────────────────┐
                        │         Jenkins (EC2)         │
                        │  1. checkout                  │
                        │  2. mvn package (WAR)         │
                        │  3. docker build → push ECR   │
                        │  4. terraform init/apply      │
                        │  5. ansible-playbook deploy   │
                        └───────┬───────────────┬───────┘
                                │               │
                     terraform  │               │ ansible
                                ▼               ▼
                 ┌───────────────────┐   ┌────────────────────┐
                 │   AWS Infra (TF)   │   │   EKS Cluster       │
                 │ VPC, subnets       │   │  ┌───────────────┐  │
                 │ EKS control plane  │──▶│  │ Tomcat Pods   │  │
                 │ Managed node group │   │  │ (Deployment)  │  │
                 │ ECR repo           │   │  └──────┬────────┘  │
                 │ IAM roles          │   │         │           │
                 │ Security groups    │   │  ┌──────▼────────┐  │
                 └───────────────────┘   │  │ MySQL Pod     │  │
                                          │  │ (StatefulSet  │  │
                                          │  │  + EBS PVC)   │  │
                                          │  └───────────────┘  │
                                          │                     │
                                          │  Service:            │
                                          │  type=LoadBalancer   │
                                          └──────────┬──────────┘
                                                      │
                                              ┌───────▼────────┐
                                              │   AWS ELB      │
                                              │ (public DNS)   │
                                              └───────┬────────┘
                                                      │
                                                    User Browser
```

---

## 4. Repo Structure (GitHub)

```
event-registration-app/
├── app/                        # Java web app
│   ├── src/main/java/...       # Servlet
│   ├── src/main/webapp/        # JSP + WEB-INF
│   ├── pom.xml
│   └── Dockerfile
├── terraform/
│   ├── vpc.tf
│   ├── eks.tf
│   ├── ecr.tf
│   ├── iam.tf
│   ├── variables.tf
│   └── outputs.tf
├── ansible/
│   ├── inventory.ini
│   ├── deploy.yml
│   └── templates/
│       ├── deployment.yml.j2
│       ├── service.yml.j2
│       ├── mysql-statefulset.yml.j2
│       └── secret.yml.j2
├── Jenkinsfile
└── README.md
```

---

## 5. Step-by-Step Walkthrough

### Step 1 — The Java/Tomcat App

A plain Servlet + JSP app (no Spring needed — keeps it lean and lets you show you understand raw Java web fundamentals, which matters in interviews).

`RegisterServlet.java` (core logic):
```java
@WebServlet("/register")
public class RegisterServlet extends HttpServlet {
    protected void doPost(HttpServletRequest req, HttpServletResponse resp)
            throws ServletException, IOException {
        String name = req.getParameter("name");
        String email = req.getParameter("email");
        String contact = req.getParameter("contact");
        String address = req.getParameter("address");

        String url = System.getenv("DB_URL");      // jdbc:mysql://mysql-service:3306/eventdb
        String user = System.getenv("DB_USER");
        String pass = System.getenv("DB_PASS");

        try (Connection conn = DriverManager.getConnection(url, user, pass)) {
            String sql = "INSERT INTO registrations (name, email, contact, address) VALUES (?, ?, ?, ?)";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, name);
                ps.setString(2, email);
                ps.setString(3, contact);
                ps.setString(4, address);
                ps.executeUpdate();
            }
        } catch (SQLException e) {
            throw new ServletException(e);
        }
        resp.sendRedirect("success.jsp");
    }
}
```

Key learning point: DB credentials come from **environment variables**, injected later by a Kubernetes `Secret` — never hardcoded. This is the pattern you'll be asked about in interviews.

`pom.xml` — package as WAR, `mysql-connector-j` as dependency, `maven-war-plugin`.

---

### Step 2 — Dockerfile

```dockerfile
FROM tomcat:10.1-jdk17-temurin
RUN rm -rf /usr/local/tomcat/webapps/ROOT
COPY target/event-registration.war /usr/local/tomcat/webapps/ROOT.war
EXPOSE 8080
CMD ["catalina.sh", "run"]
```

Learning point: stripping the default ROOT app and deploying yours as ROOT.war means the app is reachable at `/` instead of `/event-registration`.

---

### Step 3 — Terraform: Infra Provisioning

Minimal, cost-conscious layout:

**`vpc.tf`** — use the official `terraform-aws-modules/vpc/aws` module, 1 VPC, 2 public + 2 private subnets (EKS needs 2 AZs minimum), no NAT gateway if you want to shave more cost (use public subnets for nodes — acceptable for a learning project, not production).

**`eks.tf`**
```hcl
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.0"
  cluster_name    = "event-app-cluster"
  cluster_version = "1.30"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.public_subnets

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 2
      desired_size   = 1
      capacity_type  = "SPOT"   # cuts node cost ~60-70%
    }
  }
}
```

**`ecr.tf`** — one `aws_ecr_repository` for your Tomcat image.

**`outputs.tf`** — output the cluster name, endpoint, and ECR repo URL so Jenkins/Ansible can consume them.

Commands you'll run manually first (to understand what Jenkins later automates):
```bash
terraform init
terraform plan
terraform apply -auto-approve
aws eks update-kubeconfig --name event-app-cluster --region ap-southeast-1
```

**Cost note:** EKS control plane = ~$0.10/hr fixed (~$73/mo) no matter what. One `t3.medium` Spot node ≈ $10-15/mo if left running. **Run `terraform destroy` at the end of every session** — this is the single biggest cost lever you have.

---

### Step 4 — Ansible: Build, Push, Deploy

Ansible picks up after Terraform has the cluster ready. Its job:
1. Log in to ECR, build the Docker image, push it.
2. Template Kubernetes manifests (image tag, DB credentials, replica count) from Jinja2.
3. Apply them to the cluster using the `kubernetes.core.k8s` module.

`ansible/deploy.yml`:
```yaml
- hosts: localhost
  connection: local
  vars:
    ecr_repo: "{{ ecr_repo_url }}"
    image_tag: "{{ build_number }}"
  tasks:
    - name: Log in to ECR
      shell: aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin {{ ecr_repo }}

    - name: Build Docker image
      command: docker build -t {{ ecr_repo }}:{{ image_tag }} ./app

    - name: Push image
      command: docker push {{ ecr_repo }}:{{ image_tag }}

    - name: Apply MySQL StatefulSet
      kubernetes.core.k8s:
        state: present
        template: templates/mysql-statefulset.yml.j2

    - name: Apply DB Secret
      kubernetes.core.k8s:
        state: present
        template: templates/secret.yml.j2

    - name: Apply Tomcat Deployment
      kubernetes.core.k8s:
        state: present
        template: templates/deployment.yml.j2

    - name: Apply LoadBalancer Service
      kubernetes.core.k8s:
        state: present
        template: templates/service.yml.j2
```

`templates/deployment.yml.j2` (rendered by Ansible):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tomcat-app
spec:
  replicas: 1
  selector:
    matchLabels: { app: tomcat-app }
  template:
    metadata:
      labels: { app: tomcat-app }
    spec:
      containers:
        - name: tomcat
          image: "{{ ecr_repo }}:{{ image_tag }}"
          ports: [{ containerPort: 8080 }]
          envFrom:
            - secretRef: { name: db-secret }
```

`templates/service.yml.j2`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: tomcat-service
spec:
  type: LoadBalancer
  selector: { app: tomcat-app }
  ports:
    - port: 80
      targetPort: 8080
```

This Service is what triggers AWS to provision the ELB and give you a public DNS name — no domain required.

**MySQL StatefulSet** — 1 replica, `resources.requests` kept tiny (`250m` CPU / `256Mi` memory), single `PersistentVolumeClaim` (1-2Gi gp3), root/user password from the same Secret.

---

### Step 5 — Jenkins Pipeline

`Jenkinsfile`:
```groovy
pipeline {
  agent any
  environment {
    ECR_REPO = credentials('ecr-repo-url')
  }
  stages {
    stage('Checkout') {
      steps { git url: 'https://github.com/yourname/event-registration-app.git', branch: 'main' }
    }
    stage('Build WAR') {
      steps { sh 'cd app && mvn clean package' }
    }
    stage('Provision Infra') {
      steps { sh 'cd terraform && terraform init && terraform apply -auto-approve' }
    }
    stage('Deploy via Ansible') {
      steps {
        sh '''
          cd ansible
          ansible-playbook deploy.yml \
            -e ecr_repo_url=$ECR_REPO \
            -e build_number=$BUILD_NUMBER
        '''
      }
    }
    stage('Verify') {
      steps { sh 'kubectl get svc tomcat-service -o wide' }
    }
  }
}
```

Learning point: separate the **infra stage** (Terraform, idempotent, rarely changes) from the **app deploy stage** (Ansible, runs every build). In a real team these are often split into two Jenkins jobs so a code change doesn't accidentally touch infra.

---

## 6. End-to-End Flow (what actually happens)

1. You push code to GitHub.
2. Jenkins (via webhook or polling) checks out the repo.
3. Maven builds the WAR.
4. Terraform ensures VPC/EKS/ECR exist (no-op if unchanged).
5. Ansible builds the Docker image, pushes to ECR, and applies K8s manifests.
6. Kubernetes schedules the Tomcat pod, pulls the new image, and the Service (already provisioned) routes traffic to it.
7. You hit the ELB's public DNS name in a browser → registration form → submits to MySQL pod.

---

## 7. Cost-Control Checklist

- Use **Spot** capacity type for the node group.
- 1 node, `t3.medium` or `t3.small`, single AZ.
- No NAT Gateway (public subnets for nodes) — saves ~$32/mo, acceptable for learning.
- gp3 volumes, 1–2Gi for MySQL PVC.
- **`terraform destroy` after every session** — this matters more than any instance-size tweak, since the EKS control plane alone is ~$73/month if left running a full month.
- Tag everything (`Project=event-app`) so you can spot orphaned resources in the AWS console.

---

## 8. Suggested Learning Order

1. Get the Java app running locally with a local MySQL (docker-compose) — validate the app logic first.
2. Write and apply Terraform manually, `kubectl get nodes` to confirm the cluster is healthy.
3. Build/push the image and apply k8s manifests **manually** with `kubectl apply` before automating with Ansible — this cements what Ansible is abstracting away for you.
4. Wire up Ansible, run it manually.
5. Only then put it all behind Jenkins.
6. Once it all works, intentionally break something (wrong env var, bad image tag, security group misconfigured) and practice diagnosing it — this is what interview scenario questions actually test.

---

## 9. Full Project Source Files

Copy these into your repo exactly as laid out in Section 4. Every file below is complete and functional — fill in the two placeholders (`<YOUR_ECR_REPO_URL>` in Jenkins credentials, and your AWS region if not `ap-southeast-1`).

### 9.1 `app/pom.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>com.eventapp</groupId>
  <artifactId>event-registration</artifactId>
  <version>1.0.0</version>
  <packaging>war</packaging>

  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>

  <dependencies>
    <dependency>
      <groupId>jakarta.servlet</groupId>
      <artifactId>jakarta.servlet-api</artifactId>
      <version>6.0.0</version>
      <scope>provided</scope>
    </dependency>
    <dependency>
      <groupId>com.mysql</groupId>
      <artifactId>mysql-connector-j</artifactId>
      <version>8.4.0</version>
    </dependency>
  </dependencies>

  <build>
    <finalName>event-registration</finalName>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-war-plugin</artifactId>
        <version>3.4.0</version>
        <configuration>
          <failOnMissingWebXml>false</failOnMissingWebXml>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
```

### 9.2 `app/src/main/java/com/eventapp/DBUtil.java`

```java
package com.eventapp;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

public class DBUtil {
    public static Connection getConnection() throws SQLException {
        String url = System.getenv("DB_URL");   // e.g. jdbc:mysql://mysql-service:3306/eventdb
        String user = System.getenv("DB_USER");
        String pass = System.getenv("DB_PASS");
        return DriverManager.getConnection(url, user, pass);
    }
}
```

### 9.3 `app/src/main/java/com/eventapp/RegisterServlet.java`

```java
package com.eventapp;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;

@WebServlet("/register")
public class RegisterServlet extends HttpServlet {

    protected void doPost(HttpServletRequest req, HttpServletResponse resp)
            throws ServletException, IOException {

        String name = req.getParameter("name");
        String email = req.getParameter("email");
        String contact = req.getParameter("contact");
        String address = req.getParameter("address");

        String sql = "INSERT INTO registrations (name, email, contact, address) VALUES (?, ?, ?, ?)";

        try (Connection conn = DBUtil.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {

            ps.setString(1, name);
            ps.setString(2, email);
            ps.setString(3, contact);
            ps.setString(4, address);
            ps.executeUpdate();

            resp.sendRedirect("success.jsp");

        } catch (SQLException e) {
            throw new ServletException("Registration failed", e);
        }
    }
}
```

### 9.4 `app/src/main/java/com/eventapp/InitDbServlet.java`

Creates the table automatically on first startup so you don't need a manual DB step.

```java
package com.eventapp;

import jakarta.servlet.ServletContextEvent;
import jakarta.servlet.ServletContextListener;
import jakarta.servlet.annotation.WebListener;

import java.sql.Connection;
import java.sql.Statement;

@WebListener
public class InitDbServlet implements ServletContextListener {
    @Override
    public void contextInitialized(ServletContextEvent sce) {
        String createTable = "CREATE TABLE IF NOT EXISTS registrations (" +
                "id INT AUTO_INCREMENT PRIMARY KEY, " +
                "name VARCHAR(100) NOT NULL, " +
                "email VARCHAR(100) NOT NULL, " +
                "contact VARCHAR(20), " +
                "address VARCHAR(255), " +
                "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)";
        try (Connection conn = DBUtil.getConnection();
             Statement st = conn.createStatement()) {
            st.execute(createTable);
        } catch (Exception e) {
            e.printStackTrace(); // log only — don't crash startup if DB isn't ready yet
        }
    }
}
```

### 9.5 `app/src/main/webapp/index.jsp`

```jsp
<%@ page contentType="text/html;charset=UTF-8" %>
<!DOCTYPE html>
<html>
<head><title>Event Registration</title></head>
<body>
  <h2>Register for the Event</h2>
  <form action="register" method="post">
    <label>Name:</label><br>
    <input type="text" name="name" required><br><br>

    <label>Email:</label><br>
    <input type="email" name="email" required><br><br>

    <label>Contact Number:</label><br>
    <input type="text" name="contact" required><br><br>

    <label>Address:</label><br>
    <textarea name="address" required></textarea><br><br>

    <input type="submit" value="Register">
  </form>
</body>
</html>
```

### 9.6 `app/src/main/webapp/success.jsp`

```jsp
<%@ page contentType="text/html;charset=UTF-8" %>
<!DOCTYPE html>
<html>
<head><title>Registration Successful</title></head>
<body>
  <h2>Thank you — your registration was successful!</h2>
  <a href="index.jsp">Register another attendee</a>
</body>
</html>
```

### 9.7 `app/Dockerfile`

```dockerfile
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /build
COPY pom.xml .
COPY src ./src
RUN mvn -B clean package -DskipTests

FROM tomcat:10.1-jdk17-temurin
RUN rm -rf /usr/local/tomcat/webapps/ROOT
COPY --from=build /build/target/event-registration.war /usr/local/tomcat/webapps/ROOT.war
EXPOSE 8080
CMD ["catalina.sh", "run"]
```

This is a multi-stage build — Jenkins doesn't need Maven installed locally, the image builds itself.

---

### 9.8 `terraform/provider.tf`

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

### 9.9 `terraform/variables.tf`

```hcl
variable "aws_region" {
  default = "ap-southeast-1"
}

variable "cluster_name" {
  default = "event-app-cluster"
}

variable "node_instance_type" {
  default = "t3.medium"
}
```

### 9.10 `terraform/vpc.tf`

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "event-app-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = []          # no NAT gateway — nodes sit in public subnets to save cost

  enable_dns_hostnames = true
  map_public_ip_on_launch = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
}
```

### 9.11 `terraform/eks.tf`

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      capacity_type  = "SPOT"
      min_size       = 1
      max_size       = 2
      desired_size   = 1
      disk_size      = 20
    }
  }

  enable_cluster_creator_admin_permissions = true
}
```

### 9.12 `terraform/ecr.tf`

```hcl
resource "aws_ecr_repository" "app" {
  name                 = "event-app-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}
```

### 9.13 `terraform/outputs.tf`

```hcl
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repo_url" {
  value = aws_ecr_repository.app.repository_url
}
```

Run these commands once, manually, before you automate anything:
```bash
cd terraform
terraform init
terraform apply -auto-approve
aws eks update-kubeconfig --name event-app-cluster --region ap-southeast-1
kubectl get nodes
```

---

### 9.14 `ansible/inventory.ini`

```ini
[local]
localhost ansible_connection=local
```

### 9.15 `ansible/deploy.yml`

```yaml
- hosts: local
  gather_facts: false
  vars:
    ecr_repo: "{{ ecr_repo_url }}"
    image_tag: "{{ build_number }}"
    aws_region: "ap-southeast-1"
  tasks:
    - name: Log in to ECR
      shell: >
        aws ecr get-login-password --region {{ aws_region }} |
        docker login --username AWS --password-stdin {{ ecr_repo }}

    - name: Build Docker image
      command: docker build -t {{ ecr_repo }}:{{ image_tag }} ../app

    - name: Push image to ECR
      command: docker push {{ ecr_repo }}:{{ image_tag }}

    - name: Apply DB Secret
      kubernetes.core.k8s:
        state: present
        template: templates/secret.yml.j2

    - name: Apply MySQL headless service
      kubernetes.core.k8s:
        state: present
        template: templates/mysql-service.yml.j2

    - name: Apply MySQL StatefulSet
      kubernetes.core.k8s:
        state: present
        template: templates/mysql-statefulset.yml.j2

    - name: Wait for MySQL pod to be ready
      kubernetes.core.k8s_info:
        kind: Pod
        label_selectors: ["app=mysql"]
        wait: true
        wait_condition:
          type: Ready
          status: "True"
        wait_timeout: 180

    - name: Apply Tomcat Deployment
      kubernetes.core.k8s:
        state: present
        template: templates/deployment.yml.j2

    - name: Apply LoadBalancer Service
      kubernetes.core.k8s:
        state: present
        template: templates/service.yml.j2
```

### 9.16 `ansible/templates/secret.yml.j2`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
stringData:
  DB_URL: "jdbc:mysql://mysql-service:3306/eventdb"
  DB_USER: "eventuser"
  DB_PASS: "{{ mysql_password | default('ChangeMe123!') }}"
  MYSQL_ROOT_PASSWORD: "{{ mysql_root_password | default('RootChangeMe123!') }}"
  MYSQL_DATABASE: "eventdb"
  MYSQL_USER: "eventuser"
  MYSQL_PASSWORD: "{{ mysql_password | default('ChangeMe123!') }}"
```

Pass real passwords at runtime with `-e mysql_password=... -e mysql_root_password=...` (or better, pull them from AWS Secrets Manager / Jenkins credentials) — never commit real passwords to GitHub.

### 9.17 `ansible/templates/mysql-service.yml.j2`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql-service
spec:
  clusterIP: None      # headless service required for StatefulSet
  selector:
    app: mysql
  ports:
    - port: 3306
```

### 9.18 `ansible/templates/mysql-statefulset.yml.j2`

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql-service
  replicas: 1
  selector:
    matchLabels: { app: mysql }
  template:
    metadata:
      labels: { app: mysql }
    spec:
      containers:
        - name: mysql
          image: mysql:8.0
          ports: [{ containerPort: 3306 }]
          envFrom:
            - secretRef: { name: db-secret }
          resources:
            requests: { cpu: "250m", memory: "256Mi" }
            limits: { cpu: "500m", memory: "512Mi" }
          volumeMounts:
            - name: mysql-data
              mountPath: /var/lib/mysql
  volumeClaimTemplates:
    - metadata:
        name: mysql-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp3
        resources:
          requests:
            storage: 2Gi
```

### 9.19 `ansible/templates/deployment.yml.j2`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tomcat-app
spec:
  replicas: 1
  selector:
    matchLabels: { app: tomcat-app }
  template:
    metadata:
      labels: { app: tomcat-app }
    spec:
      containers:
        - name: tomcat
          image: "{{ ecr_repo }}:{{ image_tag }}"
          ports: [{ containerPort: 8080 }]
          envFrom:
            - secretRef: { name: db-secret }
          resources:
            requests: { cpu: "250m", memory: "256Mi" }
            limits: { cpu: "500m", memory: "512Mi" }
          readinessProbe:
            httpGet: { path: /, port: 8080 }
            initialDelaySeconds: 20
            periodSeconds: 10
```

### 9.20 `ansible/templates/service.yml.j2`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: tomcat-service
spec:
  type: LoadBalancer
  selector: { app: tomcat-app }
  ports:
    - port: 80
      targetPort: 8080
```

---

### 9.21 `Jenkinsfile`

The job takes one parameter, **ACTION**, with a dropdown of `Deploy` or `Destroy`. Deploy runs the build/provision/deploy stages; Destroy removes the LoadBalancer Service first (so the ELB doesn't get orphaned) and then runs `terraform destroy`. Both actions share the "Update kubeconfig" step.

```groovy
pipeline {
  agent any

  parameters {
    choice(
      name: 'ACTION',
      choices: ['Deploy', 'Destroy'],
      description: 'Deploy the app, or destroy all AWS infrastructure'
    )
  }

  environment {
    ECR_REPO       = credentials('ecr-repo-url')        // Jenkins credential: Secret text
    AWS_REGION     = 'ap-southeast-1'
    MYSQL_PWD      = credentials('mysql-app-password')  // Jenkins credential: Secret text
    MYSQL_ROOT_PWD = credentials('mysql-root-password')
  }

  stages {

    stage('Checkout') {
      steps {
        git url: 'https://github.com/yourname/event-registration-app.git', branch: 'main'
      }
    }

    // ------------------- DEPLOY PATH -------------------

    stage('Build WAR') {
      when { expression { params.ACTION == 'Deploy' } }
      steps {
        sh 'cd app && mvn -B clean package'
      }
    }

    stage('Provision Infra') {
      when { expression { params.ACTION == 'Deploy' } }
      steps {
        sh '''
          cd terraform
          terraform init -input=false
          terraform apply -auto-approve -input=false
        '''
      }
    }

    stage('Update kubeconfig') {
      steps {
        // Runs for both actions. On Destroy, the cluster might already be gone on a
        // second run — don't fail the whole pipeline if this one command can't connect.
        sh 'aws eks update-kubeconfig --name event-app-cluster --region $AWS_REGION || echo "Cluster not reachable — may not exist yet, or already destroyed"'
      }
    }

    stage('Deploy via Ansible') {
      when { expression { params.ACTION == 'Deploy' } }
      steps {
        sh '''
          cd ansible
          ansible-playbook deploy.yml \
            -e ecr_repo_url=$ECR_REPO \
            -e build_number=$BUILD_NUMBER \
            -e mysql_password=$MYSQL_PWD \
            -e mysql_root_password=$MYSQL_ROOT_PWD
        '''
      }
    }

    stage('Verify Deployment') {
      when { expression { params.ACTION == 'Deploy' } }
      steps {
        sh 'kubectl get svc tomcat-service -o wide'
        sh 'kubectl get pods -o wide'
      }
    }

    // ------------------- DESTROY PATH -------------------

    stage('Remove LoadBalancer Service') {
      when { expression { params.ACTION == 'Destroy' } }
      steps {
        // Must delete the K8s Service (and its ELB) BEFORE destroying the cluster,
        // otherwise the ELB can be orphaned and keeps costing money.
        sh 'kubectl delete svc tomcat-service --ignore-not-found=true'
      }
    }

    stage('Destroy Infra') {
      when { expression { params.ACTION == 'Destroy' } }
      steps {
        sh '''
          cd terraform
          terraform init -input=false
          terraform destroy -auto-approve -input=false
        '''
      }
    }
  }

  post {
    success {
      echo "${params.ACTION} completed successfully."
    }
    failure {
      echo "Pipeline failed during ${params.ACTION} — check stage logs above."
    }
  }
}
```

Jenkins prerequisites (set up once, manually, on the Jenkins EC2 instance): `aws-cli`, `kubectl`, `docker`, `terraform`, `ansible` + the `kubernetes.core` collection (`ansible-galaxy collection install kubernetes.core`), `maven`/JDK 17, and an IAM role/instance profile attached to the Jenkins EC2 with permissions for EKS, ECR, EC2, VPC, and IAM (scoped down once you're comfortable — start broad for learning, then tighten).

**Running it:** because the job now has a parameter, Jenkins shows a **"Build with Parameters"** button instead of "Build Now" — pick `Deploy` or `Destroy` from the dropdown each time you run it.

---

### 9.22 `README.md`

```markdown
# Event Registration App — EKS Demo Project

A Java/Tomcat event registration app deployed to Amazon EKS via a
GitHub → Jenkins → Terraform → Ansible pipeline.

## Stack
Java 17, Tomcat 10, MySQL 8 (in-cluster StatefulSet), Terraform, Ansible,
Jenkins, AWS EKS/ECR/ELB.

## Quick start (manual, before automating)
1. `cd terraform && terraform apply`
2. `aws eks update-kubeconfig --name event-app-cluster --region ap-southeast-1`
3. `cd ansible && ansible-playbook deploy.yml -e ecr_repo_url=<repo> -e build_number=manual`
4. `kubectl get svc tomcat-service` → open the EXTERNAL-IP / DNS in a browser

## Teardown (do this after every session to control cost)
Via Jenkins: run the job with **ACTION=Destroy** (Build with Parameters).

Or manually:
```bash
kubectl delete svc tomcat-service   # deletes the ELB first
cd terraform && terraform destroy -auto-approve
```

## Architecture
See `EKS-Java-Tomcat-Registration-App-Guide.md` for full design notes.
```

---

### 9.23 `docker-compose.yml` (root of repo — for local testing only, Stage 1)

```yaml
version: "3.8"
services:
  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: RootChangeMe123!
      MYSQL_DATABASE: eventdb
      MYSQL_USER: eventuser
      MYSQL_PASSWORD: ChangeMe123!
    ports:
      - "3306:3306"
    volumes:
      - mysql-data:/var/lib/mysql

  tomcat-app:
    build: ./app
    ports:
      - "8080:8080"
    environment:
      DB_URL: jdbc:mysql://mysql:3306/eventdb
      DB_USER: eventuser
      DB_PASS: ChangeMe123!
    depends_on:
      - mysql

volumes:
  mysql-data:
```

These are placeholder passwords for local testing only — fine on your laptop, never push real credentials with these values.

### 9.24 `.gitignore` (root of repo)

```gitignore
# Terraform
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfvars
!example.tfvars
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc

# Maven / Java build output
target/
*.class
*.jar
*.war

# Ansible
*.retry

# IDE
.idea/
.vscode/
*.iml

# OS
.DS_Store
Thumbs.db

# Secrets / keys — never commit these
.env
*.pem
*.key
```

Terraform state files and `.tfvars` are excluded because they can contain sensitive values (resource IDs, sometimes secrets) and because state should really live in a remote backend (S3 + DynamoDB lock table) once you're past the learning stage — committing it to Git causes merge conflicts and drift issues fast.

---

## 10. Beginner Walkthrough: Local Testing → Full AWS Deployment

This section assumes zero prior setup. Follow it top to bottom, in order — don't skip to Jenkins until Stage 3 works manually. Each stage builds confidence for the next.

### Stage 0 — Install Prerequisites (one-time, on your laptop)

| Tool | Purpose | Install |
|---|---|---|
| Java 17 JDK | Compile the app | `sdk install java 17.0.10-tem` or your OS package manager |
| Maven | Build the WAR | `sdk install maven` / `brew install maven` / `apt install maven` |
| Docker Desktop | Build & run containers locally | docker.com |
| Git | Version control | usually pre-installed; else `apt install git` |
| AWS CLI v2 | Talk to AWS | `aws --version` to check, else awscli install docs |
| Terraform CLI | Provision infra | `terraform -version` to check, else terraform.io/downloads |
| kubectl | Talk to the Kubernetes cluster | `kubectl version --client` to check |
| Ansible | Deploy to the cluster | `pip install ansible` then `ansible-galaxy collection install kubernetes.core` |

Verify each with its `--version` command before moving on. If any command isn't found, stop and fix that first — nothing later will work without this foundation.

You'll also need:
- A **free AWS account** with billing set up (card on file — this project will cost a few dollars an hour while running, detailed in Section 7).
- An **IAM user** (not root) with programmatic access — `AdministratorAccess` policy is fine for learning, tighten it later. Save the Access Key ID and Secret Access Key.
- A **GitHub account** and a new empty repo.

---

### Stage 1 — Get the Code Running Locally (no AWS yet)

This proves the app itself works before you add any infrastructure complexity.

1. Unzip the project, `cd event-registration-app`.
2. `git init && git add . && git commit -m "initial commit"`, then push to your empty GitHub repo:
   ```bash
   git remote add origin https://github.com/<you>/event-registration-app.git
   git branch -M main
   git push -u origin main
   ```
3. Add the `docker-compose.yml` file below to the project root (also listed in Section 9.23) — this spins up MySQL + your app together, exactly like the K8s deployment will, but on your laptop.
4. Run it:
   ```bash
   docker compose up --build
   ```
5. Open `http://localhost:8080` in your browser. Fill in the registration form and submit.
6. Confirm the row landed in MySQL:
   ```bash
   docker compose exec mysql mysql -ueventuser -pChangeMe123! -e "SELECT * FROM eventdb.registrations;"
   ```
7. `docker compose down` when done (add `-v` to also wipe the DB volume and start fresh next time).

**If this stage doesn't work, nothing past it will — this is the app's own logic, independent of AWS/K8s.** Debug here first.

---

### Stage 2 — Provision AWS Infrastructure Manually (no Jenkins yet)

You're now doing by hand exactly what Jenkins will later automate — so you understand what's actually happening underneath.

1. Configure AWS CLI with your IAM user's keys:
   ```bash
   aws configure
   # AWS Access Key ID: ...
   # AWS Secret Access Key: ...
   # Default region: ap-southeast-1
   # Default output format: json
   ```
   Confirm it works: `aws sts get-caller-identity` should print your account ID.

2. Provision the infrastructure:
   ```bash
   cd terraform
   terraform init      # downloads the AWS/EKS/VPC provider plugins
   terraform plan       # shows what WILL be created — read this carefully
   terraform apply       # type "yes" when prompted
   ```
   This takes **10–15 minutes** (EKS control plane provisioning is slow — this is normal, don't cancel it).

3. Point `kubectl` at your new cluster:
   ```bash
   aws eks update-kubeconfig --name event-app-cluster --region ap-southeast-1
   kubectl get nodes
   ```
   You should see 1 node in `Ready` state. If it says `Unauthorized`, your IAM user needs cluster access — re-run `terraform apply` (the `enable_cluster_creator_admin_permissions` setting in `eks.tf` should already handle this for the user that ran `apply`).

4. Note the ECR repo URL from the Terraform output:
   ```bash
   terraform output ecr_repo_url
   ```

---

### Stage 3 — Deploy to AWS Manually (still no Jenkins)

This is the stage where you prove the whole chain works end-to-end before automating anything.

1. Log in to ECR and push your image:
   ```bash
   aws ecr get-login-password --region ap-southeast-1 | \
     docker login --username AWS --password-stdin <ECR_REPO_URL>

   docker build -t <ECR_REPO_URL>:v1 ./app
   docker push <ECR_REPO_URL>:v1
   ```

2. Run the Ansible playbook by hand:
   ```bash
   cd ansible
   ansible-playbook deploy.yml \
     -e ecr_repo_url=<ECR_REPO_URL> \
     -e build_number=v1 \
     -e mysql_password=ChangeMe123! \
     -e mysql_root_password=RootChangeMe123!
   ```

3. Watch the pods come up:
   ```bash
   kubectl get pods -w
   ```
   Wait for `mysql-0` and `tomcat-app-xxxxx` to both show `Running` / `1/1 Ready`.

4. Get your public URL:
   ```bash
   kubectl get svc tomcat-service
   ```
   Look at the `EXTERNAL-IP` column — it'll be a long ELB DNS name. It can take 2-3 minutes after the Service is created before AWS finishes provisioning the load balancer and this field populates.

5. Open `http://<EXTERNAL-IP-VALUE>` in your browser — same registration form, now running on real AWS infrastructure.

6. Verify the data landed in the in-cluster MySQL:
   ```bash
   kubectl exec -it mysql-0 -- mysql -ueventuser -pChangeMe123! -e "SELECT * FROM eventdb.registrations;"
   ```

**Stop here and sit with this for a while.** You now understand exactly what Jenkins is going to automate. This is the most important stage for actually learning the concepts — don't rush to Stage 4.

---

### Stage 4 — Automate It All With Jenkins

1. **Get Jenkins running.** Easiest for learning: launch a small EC2 instance (`t3.medium`, Amazon Linux 2023) in the same AWS account, install Jenkins, Docker, `aws-cli`, `kubectl`, Terraform, Ansible, and JDK 17/Maven on it. Attach an IAM instance profile with the same permissions your IAM user has (EKS, ECR, EC2, VPC, IAM).

2. **Open Jenkins** (`http://<ec2-public-ip>:8080`), finish the setup wizard, install the suggested plugins plus **Pipeline**, **Git**, and **AWS Credentials**.

3. **Add credentials** (Manage Jenkins → Credentials):
   - `ecr-repo-url` — Secret text — your ECR repo URL from Stage 2.
   - `mysql-app-password` — Secret text — same value you used manually in Stage 3.
   - `mysql-root-password` — Secret text.

4. **Create a new Pipeline job**, point it at your GitHub repo, and set it to use the `Jenkinsfile` already in the repo root (Pipeline script from SCM). Because the `Jenkinsfile` defines a `choice` parameter, Jenkins automatically detects it on the first scan — the job will show a **"Build with Parameters"** button instead of "Build Now" from then on.

5. **Update the `git url` in the Jenkinsfile** to your actual repo URL (Section 9.21 has the file — edit and push it).

6. **Run the build.** Click "Build with Parameters," pick **ACTION → Deploy** from the dropdown, and hit Build. Watch each stage in the Jenkins console output — it's doing exactly what you did by hand in Stages 2 and 3, just automatically.

7. **Verify** the same way as Stage 3, step 4-5 — `kubectl get svc tomcat-service`, open the URL.

8. From now on: **push to GitHub → run the job with ACTION=Deploy → deploys automatically.** Optionally add a GitHub webhook (Settings → Webhooks in your repo) so Jenkins triggers on every push instead of you running it manually — though with a Deploy/Destroy choice parameter, you'll likely still want to trigger manually so you don't accidentally destroy on a push.

---

### Stage 5 — Tear Down (every time you're done for the day)

You now have two ways to tear down — use whichever fits the moment.

**Option A — via Jenkins (recommended once Stage 4 is set up):**
Click "Build with Parameters," pick **ACTION → Destroy**, and hit Build. This runs the same two steps as Option B, in order, automatically: it removes the `tomcat-service` LoadBalancer (so the ELB doesn't get orphaned) and then runs `terraform destroy`.

**Option B — manually, from your laptop:**
```bash
kubectl delete svc tomcat-service     # removes the ELB first — do this before terraform destroy
cd terraform
terraform destroy                      # type "yes" when prompted
```

Either way, double check in the AWS Console (EC2 → Load Balancers, EKS → Clusters) that nothing was left behind — orphaned ELBs are the most common leftover cost, since Terraform doesn't always know about the one K8s created for you.

---

## 11. Optional Extensions (once the base works)

- Swap the in-cluster MySQL for **RDS** (`db.t3.micro`, free-tier eligible) and compare operational differences — good talking point for interviews about managed vs self-hosted DB.
- Replace the plain LoadBalancer Service with an **AWS Load Balancer Controller + Ingress** (path-based routing, TLS via ACM) — the pattern used in most real production clusters.
- Add a Horizontal Pod Autoscaler on the Tomcat Deployment.
- Add a Jenkins stage that runs `terraform destroy` on a schedule (or manual trigger) to automate cost control.
