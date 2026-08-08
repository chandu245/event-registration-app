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
    ECR_REPO   = credentials('ecr-repo-url')  // Jenkins credential: Secret text
    AWS_REGION = 'ap-southeast-1'
    // DB passwords are no longer stored in Jenkins.
    // They are seeded into AWS Secrets Manager by Terraform and fetched at
    // deploy time by Ansible — see ansible/deploy.yml for details.

    // Jenkins home is /var/lib/jenkins — pip --user installs land in .local/bin there.
    PATH = "/var/lib/jenkins/.local/bin:/usr/local/bin:/usr/bin:/bin:${env.PATH}"
  }

  stages {

    stage('Checkout') {
      steps {
        git url: 'https://github.com/chandu245/event-registration-app.git', branch: 'main'
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
        // Passwords are injected from Jenkins environment variables TF_VAR_mysql_password
        // and TF_VAR_mysql_root_password, which you set once at the Jenkins system level
        // (Manage Jenkins → System → Global properties → Environment variables).
        // Terraform uses them to seed the AWS Secrets Manager secret on first apply.
        sh '''
          cd terraform
          terraform init -input=false
          terraform apply -auto-approve -input=false
        '''
      }
    }

    stage('Update kubeconfig') {
      steps {
        sh 'aws eks update-kubeconfig --name event-app-cluster --region $AWS_REGION || echo "Cluster not reachable — may not exist yet, or already destroyed"'
      }
    }

    stage('Fetch secret name from Terraform output') {
      when { expression { params.ACTION == 'Deploy' } }
      steps {
        script {
          // Resolve the secret name that Terraform just created so Ansible
          // can pass it into the Kubernetes deployment as AWS_SECRET_NAME.
          env.AWS_SECRET_NAME = sh(
            script: 'cd terraform && terraform output -raw db_secret_name',
            returnStdout: true
          ).trim()
          echo "DB secret name: ${env.AWS_SECRET_NAME}"
        }
      }
    }

    stage('Install Ansible') {
      when { expression { params.ACTION == 'Deploy' } }
      steps {
        sh '''
          set -e
          if command -v ansible-playbook &>/dev/null; then
            echo "ansible-playbook already installed: $(ansible-playbook --version | head -1)"
          else
            echo "ansible-playbook not found — installing via pip..."
            pip3 install --user --quiet ansible kubernetes
            # Confirm it landed where we expect
            ls ~/.local/bin/ansible-playbook
            echo "Installed: $(~/.local/bin/ansible-playbook --version | head -1)"
          fi

          # Always ensure the kubernetes.core collection is present
          ansible-galaxy collection install kubernetes.core --upgrade -p ~/.ansible/collections
        '''
      }
    }

    stage('Deploy via Ansible') {
      when { expression { params.ACTION == 'Deploy' } }
      steps {
        sh '''
          set -e
          echo "Using ansible-playbook at: $(which ansible-playbook)"
          cd ansible
          ansible-playbook -i inventory.ini deploy.yml \
            -e ecr_repo_url=$ECR_REPO \
            -e build_number=$BUILD_NUMBER \
            -e aws_secret_name=$AWS_SECRET_NAME \
            -e aws_region=$AWS_REGION
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
              echo 'Waiting for ELB DNS to be assigned...'
              sleep(time: 15, unit: 'SECONDS')
              return false
            }
          }
          env.APP_URL = "http://${dns}"
          echo "ELB DNS assigned: ${env.APP_URL}"

          timeout(time: 3, unit: 'MINUTES') {
            waitUntil {
              def code = sh(
                script: "curl -s -o /dev/null -w '%{http_code}' ${env.APP_URL} || true",
                returnStdout: true
              ).trim()
              if (code == '200') { return true }
              echo "App not responding yet (HTTP ${code}), retrying..."
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

    // ------------------- DESTROY PATH -------------------

    stage('Remove LoadBalancer Service') {
      when { expression { params.ACTION == 'Destroy' } }
      steps {
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
          echo "Deploy complete — access your app at: ${env.APP_URL}"
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
