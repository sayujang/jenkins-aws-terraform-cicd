# End-to-End DevSecOps CI/CD Pipeline
### AWS · Terraform · Docker · ECS Fargate · Jenkins · SonarQube

---

## Project Overview

This project implements a **production-grade CI/CD pipeline** for a Java-based web application, transitioning it from a traditionally deployed `.war` artifact into a containerized microservice running on serverless AWS infrastructure.

The pipeline enforces quality gates before anything reaches production     code that fails security, coverage, or style thresholds is automatically rejected. Deployments are zero-downtime rolling replacements with Slack notifications on every outcome.

```
Developer Commit → Build → Test → Code Quality → Containerize → Push to ECR → Deploy to ECS → Slack Alert
```

---

## Technology Stack

| Category | Technology |
|---|---|
| Infrastructure as Code | Terraform |
| Cloud Provider | AWS (Fargate, ECS, ECR, ALB, CloudWatch, IAM) |
| CI/CD Orchestration | Jenkins (Declarative Pipeline) |
| Build Tool | Maven |
| Language | Java 17 |
| Static Analysis | SonarQube, Checkstyle, JaCoCo, JUnit |
| Containerization | Docker (multi-stage builds) |
| Container Registry | Amazon ECR |
| Notifications | Slack API |

---

## Phase 1: Infrastructure Provisioning (Terraform)

All CI/CD infrastructure is defined as code     no manual console configuration.

- **Remote State:** S3 backend with state locking ensures safe collaboration across team members.
- **Dynamic Resource Fetching:** `data` blocks automatically resolve the latest Ubuntu 22.04 LTS AMI and the executor's current public IP for strict Security Group ingress rules     no hardcoded values.
- **Compute:** `c7i-flex.large` EC2 instances with 20 GB `gp3` EBS volumes, sized to handle heavy Maven builds and SonarQube's embedded Elasticsearch.
- **Zero-Touch Bootstrapping:** Terraform `remote-exec` and `file` provisioners inject and execute bash scripts to install Java, Nginx, PostgreSQL, and Docker     no manual SSH required.

---

## Phase 2: Continuous Integration & Security (Jenkins + SonarQube)

The pipeline follows a **fail-fast** design. Each stage must pass before the next begins. Bad code is stopped before it can reach a registry or deployment target.

### Full Pipeline Flow

```
1. Fetch Code           → Git checkout (docker branch)
        ↓
2. Build                → mvn install -DskipTests → .war artifact
        ↓
3. Unit Test            → mvn test → JUnit reports + JaCoCo coverage data
        ↓
4. Checkstyle Analysis  → mvn checkstyle:checkstyle → checkstyle-result.xml
        ↓
5. SonarQube Analysis   → sonar-scanner ships everything to SonarQube server
        ↓
6. Quality Gate         → Jenkins pauses, waits for SonarQube webhook callback
        ↓
      PASS → continue    |    FAIL → pipeline aborts, nothing is deployed
```

### What SonarQube Analyses

The scanner collects all artifacts produced in earlier stages and ships them to SonarQube in one bundle:

| Data | Source | What SonarQube does with it |
|---|---|---|
| Source code | `src/` | Scans for bugs, vulnerabilities, code smells |
| Compiled bytecode | `target/test-classes/` | Deep Java analysis (requires bytecode alongside source) |
| JUnit results | `target/surefire-reports/` | Shows test pass/fail counts on the dashboard |
| Coverage data | `target/jacoco.exec` | Shows what percentage of code is exercised by tests |
| Checkstyle XML | `target/checkstyle-result.xml` | Renders style violations on the dashboard |

### Quality Gate

A Quality Gate defines the minimum acceptable code quality threshold. If any condition is violated, SonarQube sends a `FAIL` status back to Jenkins via webhook, which triggers `abortPipeline: true`     the pipeline stops immediately and the code goes nowhere.

The webhook path (`/sonarqube-webhook`) is hardcoded into the Jenkins SonarQube plugin. Mistyping it causes Jenkins to hang indefinitely waiting for a callback that never arrives. A `timeout(time: 1, unit: 'HOURS')` wrapper is used as a safety net against network failures.

### Network Architecture (Jenkins ↔ SonarQube)

Jenkins and SonarQube communicate over **private VPC IPs**, so traffic never leaves the internal network. Two Security Group rules are required:

- SonarQube SG: allow **port 80** inbound from the Jenkins SG (Jenkins → SonarQube)
- Jenkins SG: allow **port 8080** inbound from the SonarQube SG (SonarQube webhook → Jenkins)

---

## Phase 3: Containerization & Registry (Docker + ECR)

This phase marks a fundamental shift in what the pipeline produces. Instead of a `.war` file, the artifact is now an **immutable Docker image**     Tomcat and the application baked together, runnable anywhere.

### Multi-Stage Dockerfile

A two-stage build keeps the final image lean by discarding build tools after compilation:

```
STAGE 1     BUILD (temporary, discarded)
  Maven base image
    → git clone source (docker branch)
    → mvn install
    → produces: vprofile-v2.war

STAGE 2     FINAL IMAGE (what ships to ECR)
  Tomcat base image (lightweight)
    → remove Tomcat's default app
    → COPY .war from Stage 1
    → final image: Tomcat + your app only
```

Maven, Git, and the JDK never make it into the production image.

### Dynamic Image Tagging

Every pipeline run pushes the same image to ECR under two tags:

| Tag | Example | Purpose |
|---|---|---|
| `$BUILD_NUMBER` | `vprofileappimg:9` | Pinpoints the exact build     used for rollbacks |
| `latest` | `vprofileappimg:latest` | Default pull tag     always the newest image |

### Automated Disk Cleanup

After the push, all local Docker images are force-removed from the Jenkins server:

```bash
docker rmi -f $(docker images -a -q)
```

Without this step, repeated pipeline runs fill the Jenkins disk     eventually causing builds to hang waiting for an available executor.

---

## Phase 4: Continuous Delivery (AWS ECS Fargate)

### ECS Concepts

| Concept | Analogy | Role in this project |
|---|---|---|
| **Cluster** | A datacenter/environment | `vprofile-sayuj-cluster`     where containers run |
| **Task Definition** | An EC2 Launch Template | `vprofileapptask`     blueprint (image URI, CPU, RAM, ports, log config) |
| **Service** | A process supervisor | `vprofileappsvc`     keeps 1 container running, restarts on crash, triggers deployments |
| **Task** | A running container | The actual live instance of the app |

**Why Fargate over EC2-backed ECS:** Fargate is serverless     you describe what you want (1 container, 1 vCPU, 2 GB RAM) and AWS handles the underlying compute. No EC2 instances to patch, no scaling groups to configure.

### Deployment Trigger

One AWS CLI command kicks off the deployment:

```bash
aws ecs update-service --cluster ${cluster} --service ${service} --force-new-deployment
```

`--force-new-deployment` is required because the task definition always references the `latest` tag. Without it, ECS sees no definition change and does nothing. This flag forces ECS to re-pull the image from ECR regardless.

### Zero-Downtime Rolling Replacement

```
BEFORE:  Service → Task A (old container, serving traffic)

Jenkins fires --force-new-deployment
        ↓
        Service → Task A (still running)
                → Task B (new container, pulling latest from ECR)
        ↓
        Task B passes ALB health check
        ↓
        Task A drained (no new requests sent to it)
        ↓
AFTER:  Service → Task B (new container, serving traffic)
```

There is always one healthy container serving traffic during the transition. The old container is only stopped after the new one is confirmed healthy.

### Traffic Routing

```
User Browser
  → Port 80 → Application Load Balancer
  → Port 8080 → Fargate Container (Tomcat)
```

### Security Group Architecture

The pipeline uses a single shared security group for simplicity. The correct production approach uses two:

| SG | Attached to | Inbound rule |
|---|---|---|
| `vproapp-alb-sg` | Load Balancer only | Port 80 from Anywhere |
| `vproapp-ecs-sg` | Fargate container only | Port 8080 from `vproapp-alb-sg` only |

This makes the container completely unreachable from the public internet     direct hits to its private IP on port 8080 are silently dropped.

---

## Engineering Decisions & Key Patterns

### Secret Management

Hardcoded credentials are strictly avoided throughout. All secrets are injected at runtime:

| Secret | Storage | Injection method |
|---|---|---|
| AWS Access Key + Secret | Jenkins Credentials (ID: `awscreds`) | `withAWS()` wrapper |
| SonarQube token | Jenkins Credentials (ID: `sonar-token`) | `withSonarQubeEnv()` wrapper |
| ECR URI | Pipeline `environment {}` block | Environment variable |

### Groovy String Interpolation

A subtle but critical detail: single vs double quotes behave fundamentally differently in Groovy pipeline code.

| Quote type | Behaviour | When to use |
|---|---|---|
| `'single'` | Plain literal     `$VAR` is not evaluated | Fixed strings; bash `$(command)` substitution |
| `"double"` | GString     `$VAR` is evaluated at runtime | Anything containing a Jenkins environment variable |

Examples from the pipeline:

```groovy
dockerImage.push("$BUILD_NUMBER")          // resolves to e.g. "9"
dockerImage.push('$BUILD_NUMBER')          // literal tag "$BUILD_NUMBER" on ECR

sh 'docker rmi -f $(docker images -a -q)' // bash handles $()     Groovy must not touch it
sh "docker rmi -f $(docker images -a -q)" // Groovy tries to evaluate $() and fails
```

### Idempotent Deployments

`--force-new-deployment` guarantees ECS re-pulls the updated image from ECR on every pipeline run, even when the Task Definition resource has not technically changed. Without it, a code change that only updates the `latest` image in ECR would be silently ignored by ECS.

### CloudWatch Permissions

The auto-created `ecsTaskExecutionRole` does not have permission to write logs to CloudWatch out of the box. Attaching `CloudWatchLogsFullAccess` to this role is a mandatory step     skipping it causes every container launch to fail when Tomcat tries to write its first log entry.

---

## Prerequisites & Setup Checklist

### AWS

- [ ] Create IAM user with `AmazonEC2ContainerRegistryFullAccess` + `AmazonECS_FullAccess` policies
- [ ] Generate access key and download CSV (secret key shown only once)
- [ ] Create ECR repository (`vprofileappimg`)     copy the full URI
- [ ] Create ECS Cluster (`vprofile-sayuj-cluster`) with Fargate + Container Insights enabled
- [ ] Create Task Definition (`vprofileapptask`)     set image URI, port 8080, CloudWatch logging
- [ ] Attach `CloudWatchLogsFullAccess` to `ecsTaskExecutionRole`
- [ ] Create ECS Service (`vprofileappsvc`) with ALB on port 80 → container port 8080

### Jenkins Server (via SSH)

- [ ] Install Docker Engine (not Docker Desktop)
- [ ] Add `jenkins` OS user to the `docker` group: `sudo usermod -aG docker jenkins`
- [ ] Reboot to apply group membership
- [ ] Install AWS CLI: `sudo snap install aws-cli --classic`

### Jenkins Plugins

- [ ] `Amazon Web Services SDK: All`
- [ ] `Amazon ECR`
- [ ] `Docker Pipeline`
- [ ] `CloudBees Docker Build and Publish`
- [ ] `Pipeline: AWS Steps`
- [ ] `SonarQube Scanner`

### Jenkins Configuration

- [ ] Store AWS credentials (Kind: `AWS Credentials`, ID: `awscreds`)
- [ ] Register SonarQube Scanner tool (name: `sonar6.2`)
- [ ] Add SonarQube server (name: `sonarserver`, URL: `http://<sonarqube-private-ip>`)
- [ ] Store SonarQube token (Kind: `Secret text`, ID: `sonar-token`)
- [ ] Create SonarQube webhook pointing to `http://<jenkins-private-ip>:8080/sonarqube-webhook`

### Pipeline Variables to Update

```groovy
registryCredential = 'ecr:<your-region>:awscreds'
appRegistry        = "<your-account-id>.dkr.ecr.<region>.amazonaws.com/vprofileappimg"
vprofileRegistry   = "https://<your-account-id>.dkr.ecr.<region>.amazonaws.com"
cluster            = "<your-ecs-cluster-name>"
service            = "<your-ecs-service-name>"
```

---

## Complete Jenkinsfile

```groovy
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
        cluster            = "vprofile-sayuj-cluster"
        service            = "vprofileappsvc"
    }

    stages {

        stage('Fetch Code') {
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
                    archiveArtifacts artifacts: '**/*.war'
                }
            }
        }

        stage('Unit Test') {
            steps {
                sh 'mvn test'
            }
        }

        stage('Checkstyle Analysis') {
            steps {
                sh 'mvn checkstyle:checkstyle'
            }
        }

        stage('SonarQube Analysis') {
            environment {
                scannerHome = tool 'sonar6.2'
            }
            steps {
                withSonarQubeEnv('sonarserver') {
                    sh '''${scannerHome}/bin/sonar-scanner \
                       -Dsonar.projectKey=vprofile \
                       -Dsonar.projectName=vprofile \
                       -Dsonar.projectVersion=1.0 \
                       -Dsonar.sources=src/ \
                       -Dsonar.java.binaries=target/test-classes/com/visualpathit/account/controllerTest/ \
                       -Dsonar.junit.reportsPath=target/surefire-reports/ \
                       -Dsonar.jacoco.reportsPath=target/jacoco.exec \
                       -Dsonar.java.checkstyle.reportPaths=target/checkstyle-result.xml'''
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
                    dockerImage = docker.build(appRegistry + ":$BUILD_NUMBER", "./Docker-files/app/multistage/")
                }
            }
        }

        stage('Push to ECR') {
            steps {
                script {
                    docker.withRegistry(vprofileRegistry, registryCredential) {
                        dockerImage.push("$BUILD_NUMBER")
                        dockerImage.push('latest')
                    }
                }
            }
        }

        stage('Remove Local Images') {
            steps {
                sh 'docker rmi -f $(docker images -a -q)'
            }
        }

        stage('Deploy to ECS') {
            steps {
                withAWS(credentials: 'awscreds', region: 'us-east-1') {
                    sh 'aws ecs update-service --cluster ${cluster} --service ${service} --force-new-deployment'
                }
            }
        }
    }

    post {
        always {
            slackSend channel: '#devops-pipeline',
                color: COLOR_MAP[currentBuild.currentResult],
                message: "*${currentBuild.currentResult}:* Job ${env.JOB_NAME} build ${env.BUILD_NUMBER}\nMore info: ${env.BUILD_URL}"
        }
    }
}
```

---

## Teardown

ECS resources must be deleted in a specific order to avoid dependency errors.

1. **Set desired task count to 0**     ECS → Service → Edit → Desired tasks: `0`
2. **Stop any lingering tasks**     ECS → Cluster → Tasks tab → Stop all
3. **Delete the Service**     ECS → Cluster → Services → Delete
4. **Delete the Cluster**     ECS → Clusters → Delete cluster
5. **Delete ALB and Target Group**     EC2 → Load Balancers / Target Groups
6. **Delete Security Groups**     EC2 → Security Groups (after ALB is deleted)
7. **Stop Jenkins/SonarQube EC2 instances**     Stop (not terminate) to preserve configuration for future use

---
