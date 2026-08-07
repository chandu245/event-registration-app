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
          ansible-playbook -i inventory.ini deploy.yml \
            -e ecr_repo_url=$ECR_REPO \
            -e build_number=$BUILD_NUMBER \
            -e mysql_password=$MYSQL_PWD \
            -e mysql_root_password=$MYSQL_ROOT_PWD
        '''
      }
    }

    stage('Wait for LoadBalancer & Verify') {
      when { expression { params.ACTION == 'Deploy' } }
      steps {
        script {
          // Step 1: wait for AWS to assign the ELB a DNS name (usually 1-3 min).
          def dns = ''
          timeout(time: 5, unit: 'MINUTES') {
            waitUntil {
              dns = sh(
                script: "kubectl get svc tomcat-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true",
                returnStdout: true
              ).trim()
              if (dns) {
                return true
              }
              echo 'Waiting for ELB DNS to be assigned...'
              sleep(time: 15, unit: 'SECONDS')
              return false
            }
          }
          env.APP_URL = "http://${dns}"
          echo "ELB DNS assigned: ${env.APP_URL}"

          // Step 2: DNS existing doesn't mean the ELB's health check has passed yet
          // (target registration + health checks can lag another 1-2 min) — so also
          // wait for an actual HTTP 200 before calling this a success.
          timeout(time: 3, unit: 'MINUTES') {
            waitUntil {
              def code = sh(
                script: "curl -s -o /dev/null -w '%{http_code}' ${env.APP_URL} || true",
                returnStdout: true
              ).trim()
              if (code == '200') {
                return true
              }
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
