pipeline {
  agent {
    kubernetes {
      yaml '''
        apiVersion: v1
        kind: Pod
        metadata:
          labels:
            some-label: some-label-value
        spec:
          containers:
          - name: git
            image: harbor.klaus.com/bookmanage/docker:25.0.5-git
            imagePullPolicy: IfNotPresent
            command:
            - cat
            tty: true
          - name: maven
            image: harbor.klaus.com/bookmanage/maven:v0.0.1
            imagePullPolicy: IfNotPresent
            command:
            - cat
            tty: true
          - name: docker    
            image: harbor.klaus.com/bookmanage/docker:25.0.5-git-trusted
            imagePullPolicy: IfNotPresent
            securityContext:
              privileged: true
          - name: argocd    
            image: harbor.klaus.com/bookmanage/docker:25.0.6-git-yq-trusted
            imagePullPolicy: IfNotPresent
            command:
            - cat
            tty: true
        '''
      retries 2
    }
  }
  stages {
    stage('wirteintoENV') {
        steps {
            script {
                def tag = after.substring(0, 9)
                env.TAG = tag
            }  
        }
    }      
    stage('pull code') {
      steps {
        container('git') {
          checkout scmGit(branches: [[name: '*/master']], extensions: [], userRemoteConfigs: [[url: 'http://gogs.klaus.com/klaus/book.git']])
        }
      }
    }
    stage('compile') {
      steps {
        container('maven') {
          sh 'mvn clean install'
        }
      }
    }
    stage('create image') {
      steps {
        container('docker') {
            withCredentials([usernamePassword(credentialsId: 'harbor', passwordVariable: 'pass', usernameVariable: 'user')]) {
                sh "docker build . -t harbor.klaus.com/bookmanage/project:${env.TAG}"
                sh "docker login -u ${user} -p ${pass} harbor.klaus.com"
                sh "docker push harbor.klaus.com/bookmanage/project:${env.TAG}"
            }
        }
      }
    }
    stage('deploy') {
        steps {
            container('argocd') {
                script {
                    sh """
                    git clone "http://gogs.klaus.com/klaus/bookhelm.git"
                    cd bookhelm
                    yq e '.image.tagj = "${env.TAG}"' -i helm/values.yaml 
                    git config --global user.email "you@example.com"
                    git config --global user.name "klaus"
                    git add .
                    git commit -m "${env.TAG}"
                    git push http://klaus:123456@gogs.klaus.com/klaus/bookhelm.git master
                    """
                }
            }
        }
    }
  }
  post { 
    success {
            script {
                sh '''
                curl -s -X POST "https://oapi.dingtalk.com/robot/send?access_token=ded79a9b3d965ad1c63aee3be8c2cebb07e80e05fb1d6d7918115ee3fb01e1b9" \
                -H 'Content-Type: application/json' \
                -d '{
                  "msgtype": "text",
                  "text": {
                    "content": "From klaus: Your project has been successfully deployed"
                  }
                }'
                '''
            }
        }
    failure {
            script {
                sh '''
                curl -s -X POST "https://oapi.dingtalk.com/robot/send?access_token=ded79a9b3d965ad1c63aee3be8c2cebb07e80e05fb1d6d7918115ee3fb01e1b9" \
                -H 'Content-Type: application/json' \
                -d '{
                  "msgtype": "text",
                  "text": {
                    "content": "From klaus: your deployment fail, something went wrong, please check jenkins"
                  }
                }'
                '''
            }
        }
  }
}
