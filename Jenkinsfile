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
    ECR_REPO   = credentials('ecr-repo-url')  // Only Jenkins credential needed
    AWS_REGION = 'ap-southeast-1'
    // No DB passwords here — Terraform generates them via random_password and
    // stores them in AWS Secrets Manager. ESO syncs them into K8s automatically.

    // pip --user installs land in the Jenkins home .local/bin
    PATH = "/var/lib/jenkins/.local/bin:/usr/local/bin:/usr/bin:/bin:${env.PATH}"
  }

  stages {

    stage('Checkout') {
      steps {
        git url: 'https://github.com/chandu245/event-registration-app.git', branch: 'main'
      }
    }

    // ── DEPLOY ─────────────────────────────────────────────────────────────

    stage('Provision Infra') {
      when { expression { params.ACTION == 'Deploy' } }
      steps {
        // Terraform generates passwords internally (random_password resource).
        // No variables, no secrets, no credentials needed here.
        sh '''
          set -e
          cd terraform
          terraform init -input=false
          terraform apply -auto-approve -input=false
        '''
      }
    }

    stage('Update kubeconfig') {
      steps {
        sh '''
          aws eks update-kubeconfig --name event-app-cluster --region $AWS_REGION \
            || echo "Cluster not reachable — may not exist yet, or already destroyed"
        '''
      }
    }

    stage('Fetch Terraform outputs') {
      when { expression { params.ACTION == 'Deploy' } }
      steps {
        script {
          env.AWS_SECRET_NAME = sh(
            script: 'cd terraform && terraform output -raw db_secret_name',
            returnStdout: true
          ).trim()
          env.ESO_ROLE_ARN = sh(
            script: 'cd terraform && terraform output -raw eso_role_arn',
            returnStdout: true
          ).trim()
          echo "DB secret name: ${env.AWS_SECRET_NAME}"
          echo "ESO role ARN:   ${env.ESO_ROLE_ARN}"
        }
      }
    }

    stage('Deploy via Ansible') {
      when { expression { params.ACTION == 'Deploy' } }
      steps {
        sh '''
          set -e
          echo "Using ansible-playbook at: $(which ansible-playbook)"
          # Ensure helm is installed (required for ESO install task in Ansible)
          if ! command -v helm &>/dev/null; then
            echo "Installing helm..."
            curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
          fi
          cd ansible
          ansible-playbook -i inventory.ini deploy.yml \
            -e ecr_repo_url=$ECR_REPO \
            -e build_number=$BUILD_NUMBER \
            -e aws_secret_name=$AWS_SECRET_NAME \
            -e aws_region=$AWS_REGION \
            -e eso_role_arn=$ESO_ROLE_ARN
        '''
      }
    }

    stage('Wait for LoadBalancer & Verify') {
      when { expression { params.ACTION == 'Deploy' } }
      steps {
        script {
          def dns = ''
          timeout(time: 5, unit: 'MINUTES') {
            waitUntil {
              dns = sh(
                script: "kubectl get svc tomcat-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true",
                returnStdout: true
              ).trim()
              if (dns) { return true }
              echo 'Waiting for ELB DNS...'
              sleep(time: 15, unit: 'SECONDS')
              return false
            }
          }
          env.APP_URL = "http://${dns}"

          timeout(time: 3, unit: 'MINUTES') {
            waitUntil {
              def code = sh(
                script: "curl -s -o /dev/null -w '%{http_code}' ${env.APP_URL} || true",
                returnStdout: true
              ).trim()
              if (code == '200') { return true }
              echo "HTTP ${code} — waiting..."
              sleep(time: 15, unit: 'SECONDS')
              return false
            }
          }

          echo "=================================================="
          echo " App is live at: ${env.APP_URL}"
          echo "=================================================="
        }
        sh 'kubectl get pods -o wide'
      }
    }

    // ── DESTROY ────────────────────────────────────────────────────────────

    stage('Remove LoadBalancer Service') {
      when { expression { params.ACTION == 'Destroy' } }
      steps {
        // Delete the ELB before destroying the cluster — otherwise the ELB
        // becomes orphaned and keeps charging money.
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
      script {
        if (params.ACTION == 'Deploy' && env.APP_URL) {
          echo "Deploy complete — ${env.APP_URL}"
        } else {
          echo "${params.ACTION} completed successfully."
        }
      }
    }
    failure {
      echo "Pipeline failed during ${params.ACTION} — check stage logs above."
    }
  }
}
