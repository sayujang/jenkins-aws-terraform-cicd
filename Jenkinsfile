def COLOR_MAP = [
    'SUCCESS': 'good',
    'FAILURE': 'danger',
]

pipeline {
    agent any

    tools {
        maven "MAVEN3.9.9"
        jdk "JDK17"
    }

    environment {
        registryCredential = 'ecr:us-east-1:awscreds'
        appRegistry        = "061039781847.dkr.ecr.us-east-1.amazonaws.com/vprofileappimg"
        vprofileRegistry   = "https://061039781847.dkr.ecr.us-east-1.amazonaws.com"
        cluster            = "vprofile-sayuj-cluster"  // ECS cluster name — must match exactly
        service            = "vprofileappsvc"           // ECS service name — must match exactly
    }

    stages {

        stage('fetch code') {
            steps {
                git branch: 'docker', url: 'https://github.com/hkhcoder/vprofile-project.git'
            }
        }

        stage('Build') {
            steps {
                sh 'mvn install -DskipTests'
            }
            post {
                success {
                    echo "archiving artifact"
                    archiveArtifacts artifacts: '**/*.war'
                }
            }
        }

        stage('unit test') {
            steps {
                sh 'mvn test'
            }
        }

        stage('checkstyle analysis') {
            steps {
                sh 'mvn checkstyle:checkstyle'
            }
        }

        stage('Sonar code analysis') {
            environment {
                scannerHome = tool 'sonar6.2'
            }
            steps {
                withSonarQubeEnv('sonarserver') {
                    sh '''${scannerHome}/bin/sonar-scanner -Dsonar.projectKey=vprofile \
                       -Dsonar.projectName=vprofile \
                       -Dsonar.projectVersion=1.0 \
                       -Dsonar.sources=src/ \
                       -Dsonar.java.binaries=target/test-classes/com/visualpathit/account/controllerTest/ \
                       -Dsonar.junit.reportsPath=target/surefire-reports/ \
                       -Dsonar.jacoco.reportsPath=target/jacoco.exec \
                       -Dsonar.java.checkstyle.reportPaths=target/checkstyle-result.xml
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 1, unit: 'HOURS') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Build App Image') {
            steps {
                script {
                    // ":$BUILD_NUMBER" needs double quotes — variable must resolve
                    dockerImage = docker.build(appRegistry + ":$BUILD_NUMBER", "./Docker-files/app/multistage/")
                }
            }
        }

        stage('Upload App Image') {
            steps {
                script {
                    docker.withRegistry(vprofileRegistry, registryCredential) {
                        dockerImage.push("$BUILD_NUMBER")  // double quotes: variable must resolve
                        dockerImage.push('latest')          // single quotes: fixed string
                    }
                }
            }
        }

        stage('Remove images from jenkins') {
            steps {
                // Single quotes mandatory: $(command) is bash, not Groovy
                sh 'docker rmi -f $(docker images -a -q)'
            }
        }

        stage('Deploy to ECS') {
            steps {
                // withAWS injects awscreds (access key + secret key) into the environment
                // so the aws CLI can authenticate with AWS automatically
                withAWS(credentials: 'awscreds', region: 'us-east-1') {
                    sh 'aws ecs update-service --cluster ${cluster} --service ${service} --force-new-deployment'
                }
            }
        }
    }

    post {
        always {
            echo 'Slack Notifications.'
            slackSend channel: '#all-devopslearners',
                color: COLOR_MAP[currentBuild.currentResult],
                message: "*${currentBuild.currentResult}:* Job ${env.JOB_NAME} build ${env.BUILD_NUMBER} \n More info at: ${env.BUILD_URL}"
        }
    }
}