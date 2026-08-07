# Event Registration App — EKS Demo Project

A Java/Tomcat event registration app deployed to Amazon EKS via a
GitHub → Jenkins → Terraform → Ansible pipeline.

## Stack
Java 17, Tomcat 10, MySQL 8 (in-cluster StatefulSet), Terraform, Ansible,
Jenkins, AWS EKS/ECR/ELB.

## Repo layout
```
app/            Java/Tomcat source, pom.xml, Dockerfile
terraform/      VPC, EKS, ECR provisioning
ansible/        Build/push image + deploy Kubernetes manifests
Jenkinsfile     CI/CD pipeline
```

## Quick start (manual, before automating with Jenkins)
1. `cd terraform && terraform apply`
2. `aws eks update-kubeconfig --name event-app-cluster --region ap-southeast-1`
3. `cd ansible && ansible-playbook deploy.yml -e ecr_repo_url=<repo> -e build_number=manual -e mysql_password=<pwd> -e mysql_root_password=<pwd>`
4. `kubectl get svc tomcat-service` → open the EXTERNAL-IP / DNS in a browser

## Jenkins job
The `Jenkinsfile` defines an `ACTION` choice parameter — `Deploy` or `Destroy`.
Run the job via "Build with Parameters" and pick the one you want.

## Teardown (do this after every session to control cost)
Via Jenkins: run the job with **ACTION=Destroy**.

Or manually:
```bash
kubectl delete svc tomcat-service   # deletes the ELB first
cd terraform && terraform destroy -auto-approve
```

## Architecture
See the accompanying design doc (EKS-Java-Tomcat-Registration-App-Guide.md) for
full architecture notes, cost-control checklist, and a suggested learning order.

## Security note
Never commit real DB passwords to GitHub. Pass them at runtime via
Jenkins credentials / Ansible extra-vars, or better, pull from AWS Secrets Manager.
