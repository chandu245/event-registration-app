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
          ansible-playbook -i inventory.ini deploy.yml \
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
