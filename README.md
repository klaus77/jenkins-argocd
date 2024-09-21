# 使用Jenkins+Argocd实现CICD

## 项目说明
本项目基于 Kubernetes，采用 Jenkins 和 GitOps 来实现一套完整的 CI/CD。

## 项目架构与组成部分
![](./presentation/图片1.png)
### 环境搭建
- Jenkins on Kubernetes: [GitHub Repository](https://github.com/klaus77/Jenkins-gogs-harbor-argocd.git)
- Gogs on Kubernetes: [GitHub Repository](https://github.com/klaus77/Jenkins-gogs-harbor-argocd.git)
- Harbor on Kubernetes: [GitHub Repository](https://github.com/klaus77/Jenkins-gogs-harbor-argocd.git)
- ArgoCD on Kubernetes: [Argo CD Documentation](https://argo-cd.readthedocs.io/en/stable/getting_started/)

## 具体配置

### 在 Jenkins 上需要安装的插件
- Pipeline
- Kubernetes
- Generic Webhook Trigger Plugin
- Git
- Role Based Authorization Strategy

在 Jenkins 上采用动态 Slave，配置 Kubernetes 集群信息。
![](./presentation/图片2.png)
![](./presentation/图片3.png)
### 创建 Gogs 仓库
- 开发代码仓库
![](./presentation/图片4.png)
- 部署模板仓库
![](./presentation/图片5.png)

### 创建 Harbor 镜像仓库
![](./presentation/图片6.png)
### 配置 CoreDNS
![](./presentation/图片7.png)
### 编写项目部署 Dockerfile
![](./presentation/图片8.png)
### 制作信任自己的 Harbor 镜像仓库并且有 yq 工具的 Docker in Docker 镜像
![](./presentation/图片9.png)
### 设定两个 Webhook
- 用来触发 Pipeline
![](./presentation/图片10.png)
- 用来触发 ArgoCD
  - 在 ArgoCD 的 `argocd-secret` 中配置触发 ArgoCD 的 token
    ![](./presentation/图片11.png)
  - 在 Gogs 中配置 Webhook
    ![](./presentation/图片12.png)

## 项目整体思路

### Pipeline
- 拉取代码，编译构建
- 将 Maven 的中心仓库更改成阿里云的仓库
- 制作信任 Harbor 镜像仓库的 Docker in Docker 镜像
- 采用 Docker in Docker 的方式打包镜像并推送至 Harbor 镜像仓库
- 根据镜像的版本号更新 Helm 仓库，ArgoCD 自动感知并自动部署
- 钉钉告警

# 项目实现结果

- 部署项目展示
![](./presentation/图片13.png)
- 修改开发源码并提交
![](./presentation/图片14.png)
![](./presentation/图片15.png)
- 通过 Webhook 触发 Jenkins 的 Pipeline
  创建动态 Jenkins Slave
  ![](./presentation/图片16.png)
- Pipeline 运行成功
![](./presentation/图片17.png)
- 钉钉告警成功
![](./presentation/图片18.png)
- Pipeline 修改 Helm 部署模板提交
![](./presentation/图片19.png)
- 触发 Webhook，Argocd 自动感知自动部署
![](./presentation/图片20.png)
![](./presentation/图片21.png)
- 结果，可以看到项目发生了改变
![](./presentation/图片22.png)

- Pipeline 源码
```groovy
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
    stage('writeIntoENV') {
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
          withCredentials([usernamePassword(credentialsId: 'gogs', passwordVariable: 'gogspassword', usernameVariable: 'gogouser')]) {
            script {
              sh '''
              git clone "http://gogs.klaus.com/klaus/bookhelm.git"
              cd bookhelm
              yq e '.image.tagj = "${env.TAG}"' -i helm/values.yaml
              git config --global user.email "you@example.com"
              git config --global user.name "klaus"
              git add .
              git commit -m "${env.TAG}"
              git push http://${gogouser}:${gogspassword}@gogs.klaus.com/klaus/bookhelm.git master
              '''
            }
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
            "content": "From klaus: Your deployment failed, something went wrong. Please check Jenkins."
          }
        }'
        '''
      }
    }
  }
}
