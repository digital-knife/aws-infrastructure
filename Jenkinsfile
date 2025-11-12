pipeline {
    agent {
        kubernetes {
            inheritFrom 'terraform-cloud-provisioner'
            defaultContainer 'jnlp'
            yaml '''
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins
  containers:
  - name: jnlp
    image: jenkins/inbound-agent:latest
    args: ["$(JENKINS_SECRET)", "$(JENKINS_NAME)"]
    tty: true
    securityContext:
      runAsUser: 0
    resources:
      limits:
        memory: "1Gi"
        cpu: "1000m"
      requests:
        memory: "512Mi"
        cpu: "512m"
    volumeMounts:
      - mountPath: /home/jenkins/agent
        name: workspace-volume
  volumes:
    - name: workspace-volume
      emptyDir: {}
'''
        }
    }

    environment {
        TERRAFORM_VERSION = '1.9.5'
        TERRAGRUNT_VERSION = '0.93.4'
        AWS_REGION = "${params.aws_region}"
        VPC_NAME = "${params.vpc_name}"
        VPC_TAG = "${params.vpc_tag}"
        PUBLIC_SUBNET_CIDR = "${params.public_subnet_cidr}"
        PRIVATE_SUBNET_CIDR = "${params.private_subnet_cidr}"
        INSTANCE_TYPE = "${params.instance_type}"
        S3_BUCKET_NAME = "${params.s3_bucket_name}"
        ENV = "${params.environment ?: 'dev'}"
        ACTION = "${params.action}"
        DESTROY_CONFIRM = "${params.destroy}"
    }

    parameters {
        choice(
            name: 'environment', 
            choices: ['dev', 'prod'], 
            description: '''Environment Selection (CIDR auto-assigned):
            • dev  → VPC CIDR: 10.0.0.0/16 (subnets must use 10.0.x.x)
            • prod → VPC CIDR: 10.1.0.0/16 (subnets must use 10.1.x.x)'''
        )
        choice(
            name: 'aws_region', 
            choices: ['us-east-1', 'us-east-2', 'us-west-1', 'us-west-2'], 
            description: 'AWS Region where resources will be deployed'
        )
        string(
            name: 'vpc_name', 
            defaultValue: '', 
            description: '''VPC Name (optional):
            • Leave empty to use default naming (dev-vpc or prod-vpc)
            • Provide custom name for easier identification in AWS Console'''
        )
        string(
            name: 'vpc_tag', 
            defaultValue: '', 
            description: '''Additional VPC Tag (optional):
            • Leave empty for standard tagging only
            • Add custom tag for team/project identification (e.g., "team-alpha", "project-x")'''
        )
        string(
            name: 'public_subnet_cidr', 
            defaultValue: '', 
            description: '''Public Subnet CIDR (optional):
            • Leave empty for auto-assignment (recommended)
            • dev:  Must be within 10.0.0.0/16 (e.g., 10.0.1.0/24)
            • prod: Must be within 10.1.0.0/16 (e.g., 10.1.1.0/24)
            • Job will FAIL if subnet is outside VPC range'''
        )
        string(
            name: 'private_subnet_cidr', 
            defaultValue: '', 
            description: '''Private Subnet CIDR (optional):
            • Leave empty for auto-assignment (recommended)
            • dev:  Must be within 10.0.0.0/16 (e.g., 10.0.2.0/24)
            • prod: Must be within 10.1.0.0/16 (e.g., 10.1.2.0/24)
            • Job will FAIL if subnet is outside VPC range'''
        )
        choice(
            name: 'instance_type', 
            choices: ['', 't3.micro', 't3.small'], 
            description: '''EC2 Instance Type:
            • Leave empty to use environment default (dev: t3.micro, prod: t3.small)
            • t3.micro: 2 vCPU, 1GB RAM
            • t3.small: 2 vCPU, 2GB RAM'''
        )
        string(
            name: 's3_bucket_name', 
            defaultValue: '', 
            description: '''S3 Bucket Name (optional):
            • Leave empty to use environment default (demo-bucket-dev or demo-bucket-prod)
            • Must be globally unique across ALL AWS accounts
            • Use lowercase, numbers, and hyphens only'''
        )
        choice(
            name: 'action', 
            choices: ['create', 'update', 'destroy'], 
            description: '''Action to Perform:
            • Create:  Provision new infrastructure
            • Update:  Modify existing infrastructure
            • Destroy: DELETE all resources (requires confirmation checkbox)'''
        )
        booleanParam(
            name: 'destroy', 
            defaultValue: false, 
            description: '''DESTROY CONFIRMATION (required for destroy action):
            • DESTROYING CANNOT BE UNDONE - all data will be PERMANENTLY deleted
            • Backup any important data before proceeding'''
        )
    }

    stages {
        stage('Set ENV Default') {
            steps {
                script {
                    if (!params.environment || params.environment == '') {
                        env.ENV = 'dev'
                    } else {
                        env.ENV = params.environment
                    }
                    
                    // Set environment-specific CIDR (locked per environment)
                    if (env.ENV == 'dev') {
                        env.VPC_CIDR = '10.0.0.0/16'
                        env.VPC_CIDR_PREFIX = '10.0'
                    } else if (env.ENV == 'prod') {
                        env.VPC_CIDR = '10.1.0.0/16'
                        env.VPC_CIDR_PREFIX = '10.1'
                    }
                    
                    echo "Environment: ${env.ENV}"
                    echo "VPC CIDR (environment-locked): ${env.VPC_CIDR}"
                }
            }
        }

        stage('Checkout SCM') {
            steps {
                checkout scm
            }
        }

        stage('Debug Directory Structure') {
            steps {
                sh '''
                    #!/bin/bash
                    set -e
                    echo "=========================================="
                    echo "Selected Parameters:"
                    echo "=========================================="
                    echo "ENV: ${ENV}"
                    echo "ACTION: ${ACTION}"
                    echo "AWS_REGION: ${AWS_REGION}"
                    echo "VPC_CIDR (environment-locked): ${VPC_CIDR}"
                    echo "VPC_NAME: ${VPC_NAME}"
                    echo "VPC_TAG: ${VPC_TAG}"
                    echo "PUBLIC_SUBNET_CIDR: ${PUBLIC_SUBNET_CIDR}"
                    echo "PRIVATE_SUBNET_CIDR: ${PRIVATE_SUBNET_CIDR}"
                    echo "S3_BUCKET_NAME: ${S3_BUCKET_NAME}"
                    echo "INSTANCE_TYPE: ${INSTANCE_TYPE}"
                    echo "=========================================="
                    echo "Listing repository structure:"
                    ls -R
                    echo "Checking contents of terragrunt.hcl for environment: ${ENV}"
                    if [ -z "${ENV}" ]; then
                        echo "Warning: ENV is empty, defaulting to dev"
                        ENV="dev"
                    fi
                    if [ -f "${ENV}/terragrunt.hcl" ]; then
                        echo "Contents of ${ENV}/terragrunt.hcl:"
                        cat ${ENV}/terragrunt.hcl
                    else
                        echo "Warning: ${ENV}/terragrunt.hcl not found"
                    fi
                    if [ -f "root.hcl" ]; then
                        echo "Contents of root.hcl:"
                        cat root.hcl
                    else
                        echo "Warning: root.hcl not found"
                    fi
                '''
            }
        }

        stage('Setup Tools') {
            steps {
                sh '''
                    #!/bin/bash
                    set -e
                    echo "Installing dependencies..."
                    apt-get update && apt-get install -y unzip curl

                    echo "Installing AWS CLI..."
                    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                    unzip awscliv2.zip
                    ./aws/install
                    rm -rf aws awscliv2.zip

                    echo "Installing Terraform..."
                    curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o terraform.zip
                    unzip terraform.zip
                    mv terraform /usr/local/bin/
                    rm terraform.zip

                    echo "Installing Terragrunt..."
                    curl -fsSL https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_amd64 -o terragrunt
                    chmod +x terragrunt
                    mv terragrunt /usr/local/bin/
                    
                    echo "Verifying installations..."
                    aws --version
                    terraform --version
                    terragrunt --version
                '''
            }
        }

        stage('Param Validation') {
            steps {
                script {
                    // Validate destroy action
                    if (env.ACTION == 'destroy' && env.DESTROY_CONFIRM != 'true') {
                        error('VALIDATION FAILED: Destroy action requires the "destroy" checkbox to be checked for safety. Please confirm and rerun.')
                    }
                    
                    // Validate environment
                    if (env.ENV == '') {
                        error('VALIDATION FAILED: Environment parameter is required. Please select "dev" or "prod".')
                    }
                    
                    // Only validate subnet CIDRs if they are actually provided
                    if (env.PUBLIC_SUBNET_CIDR && env.PUBLIC_SUBNET_CIDR != '' && env.PUBLIC_SUBNET_CIDR != 'null') {
                        if (!env.PUBLIC_SUBNET_CIDR.startsWith(env.VPC_CIDR_PREFIX)) {
                            error("VALIDATION FAILED: Public subnet CIDR '${env.PUBLIC_SUBNET_CIDR}' is outside the ${env.ENV} VPC range (${env.VPC_CIDR}). Public subnet must start with ${env.VPC_CIDR_PREFIX}.x.x")
                        }
                        echo "Public subnet CIDR validated: ${env.PUBLIC_SUBNET_CIDR}"
                    } else {
                        echo "Public subnet CIDR: Using auto-assignment"
                    }
                    
                    // Only validate private subnet CIDR if it's actually provided
                    if (env.PRIVATE_SUBNET_CIDR && env.PRIVATE_SUBNET_CIDR != '' && env.PRIVATE_SUBNET_CIDR != 'null') {
                        if (!env.PRIVATE_SUBNET_CIDR.startsWith(env.VPC_CIDR_PREFIX)) {
                            error("VALIDATION FAILED: Private subnet CIDR '${env.PRIVATE_SUBNET_CIDR}' is outside the ${env.ENV} VPC range (${env.VPC_CIDR}). Private subnet must start with ${env.VPC_CIDR_PREFIX}.x.x")
                        }
                        echo "Private subnet CIDR validated: ${env.PRIVATE_SUBNET_CIDR}"
                    } else {
                        echo "Private subnet CIDR: Using auto-assignment"
                    }
                    
                    // Display locked CIDR for transparency
                    echo "=========================================="
                    echo "Environment: ${env.ENV}"
                    echo "VPC CIDR locked: ${env.VPC_CIDR}"
                    echo "Subnets must use: ${env.VPC_CIDR_PREFIX}.x.x"
                    echo "All validations passed"
                    echo "=========================================="
                }
            }
        }

        stage('Terraform Init') {
            when {
                anyOf {
                    expression { env.ACTION == 'create' }
                    expression { env.ACTION == 'update' }
                    expression { env.ACTION == 'destroy' }
                }
            }
            steps {
                withCredentials([aws(credentialsId: 'd690f807-aa7f-4f36-8d44-8d0ba71dc975', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        #!/bin/bash
                        set -e
                        export AWS_DEFAULT_REGION=${AWS_REGION}
                        echo "Checking directory structure for environment: ${ENV}"
                        if [ ! -d "${ENV}" ]; then
                            echo "Error: Directory ${ENV} does not exist"
                            exit 1
                        fi
                        if [ ! -f "${ENV}/terragrunt.hcl" ]; then
                            echo "Error: terragrunt.hcl not found in ${ENV}"
                            exit 1
                        fi
                        if [ ! -f "root.hcl" ]; then
                            echo "Warning: root.hcl not found, terragrunt may fail if it includes this file"
                        fi
                        cd ${ENV}
                        echo "Running terragrunt init in $(pwd)"
                        terragrunt init
                    '''
                }
            }
        }

        stage('Terraform Plan') {
            when { expression { env.ACTION == 'create' || env.ACTION == 'update' } }
            steps {
                withCredentials([aws(credentialsId: 'd690f807-aa7f-4f36-8d44-8d0ba71dc975', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        #!/bin/bash
                        set -e
                        export AWS_DEFAULT_REGION=${AWS_REGION}
                        cd ${ENV}
                        echo "Running terragrunt plan in $(pwd)"
                        
                        CMD="terragrunt plan"
                        
                        if [ -n "${AWS_REGION}" ] && [ "${AWS_REGION}" != "null" ]; then
                            CMD="${CMD} -var=\"aws_region=${AWS_REGION}\""
                            echo "Overriding aws_region with: ${AWS_REGION}"
                        fi
                        
                        if [ -n "${VPC_CIDR}" ] && [ "${VPC_CIDR}" != "null" ]; then
                            CMD="${CMD} -var=\"vpc_cidr=${VPC_CIDR}\""
                            echo "Overriding vpc_cidr with: ${VPC_CIDR}"
                        fi
                        
                        if [ -n "${VPC_NAME}" ] && [ "${VPC_NAME}" != "null" ]; then
                            CMD="${CMD} -var=\"vpc_name=${VPC_NAME}\""
                            echo "Overriding vpc_name with: ${VPC_NAME}"
                        fi
                        
                        if [ -n "${VPC_TAG}" ] && [ "${VPC_TAG}" != "null" ]; then
                            CMD="${CMD} -var=\"vpc_tag=${VPC_TAG}\""
                            echo "Overriding vpc_tag with: ${VPC_TAG}"
                        fi
                        
                        if [ -n "${PUBLIC_SUBNET_CIDR}" ] && [ "${PUBLIC_SUBNET_CIDR}" != "null" ]; then
                            CMD="${CMD} -var=\"public_subnet_cidr=${PUBLIC_SUBNET_CIDR}\""
                            echo "Overriding public_subnet_cidr with: ${PUBLIC_SUBNET_CIDR}"
                        fi
                        
                        if [ -n "${PRIVATE_SUBNET_CIDR}" ] && [ "${PRIVATE_SUBNET_CIDR}" != "null" ]; then
                            CMD="${CMD} -var=\"private_subnet_cidr=${PRIVATE_SUBNET_CIDR}\""
                            echo "Overriding private_subnet_cidr with: ${PRIVATE_SUBNET_CIDR}"
                        fi
                        
                        if [ -n "${INSTANCE_TYPE}" ] && [ "${INSTANCE_TYPE}" != "null" ]; then
                            CMD="${CMD} -var=\"instance_type=${INSTANCE_TYPE}\""
                            echo "Overriding instance_type with: ${INSTANCE_TYPE}"
                        fi
                        
                        if [ -n "${S3_BUCKET_NAME}" ] && [ "${S3_BUCKET_NAME}" != "null" ]; then
                            CMD="${CMD} -var=\"s3_bucket_name=${S3_BUCKET_NAME}\""
                            echo "Overriding s3_bucket_name with: ${S3_BUCKET_NAME}"
                        fi
                        
                        echo "=========================================="
                        echo "Executing: ${CMD}"
                        echo "=========================================="
                        eval "${CMD}"
                    '''
                    input "Approve plan? Review the output above and proceed to apply."
                }
            }
        }

        stage('Terraform Apply') {
            when { expression { env.ACTION == 'create' || env.ACTION == 'update' } }
            steps {
                withCredentials([aws(credentialsId: 'd690f807-aa7f-4f36-8d44-8d0ba71dc975', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        #!/bin/bash
                        set -e
                        export AWS_DEFAULT_REGION=${AWS_REGION}
                        cd ${ENV}
                        echo "Running terragrunt apply in $(pwd)"
                        
                        CMD="terragrunt apply -auto-approve"
                        
                        if [ -n "${AWS_REGION}" ] && [ "${AWS_REGION}" != "null" ]; then
                            CMD="${CMD} -var=\"aws_region=${AWS_REGION}\""
                        fi
                        
                        if [ -n "${VPC_CIDR}" ] && [ "${VPC_CIDR}" != "null" ]; then
                            CMD="${CMD} -var=\"vpc_cidr=${VPC_CIDR}\""
                        fi
                        
                        if [ -n "${VPC_NAME}" ] && [ "${VPC_NAME}" != "null" ]; then
                            CMD="${CMD} -var=\"vpc_name=${VPC_NAME}\""
                        fi
                        
                        if [ -n "${VPC_TAG}" ] && [ "${VPC_TAG}" != "null" ]; then
                            CMD="${CMD} -var=\"vpc_tag=${VPC_TAG}\""
                        fi
                        
                        if [ -n "${PUBLIC_SUBNET_CIDR}" ] && [ "${PUBLIC_SUBNET_CIDR}" != "null" ]; then
                            CMD="${CMD} -var=\"public_subnet_cidr=${PUBLIC_SUBNET_CIDR}\""
                        fi
                        
                        if [ -n "${PRIVATE_SUBNET_CIDR}" ] && [ "${PRIVATE_SUBNET_CIDR}" != "null" ]; then
                            CMD="${CMD} -var=\"private_subnet_cidr=${PRIVATE_SUBNET_CIDR}\""
                        fi
                        
                        if [ -n "${INSTANCE_TYPE}" ] && [ "${INSTANCE_TYPE}" != "null" ]; then
                            CMD="${CMD} -var=\"instance_type=${INSTANCE_TYPE}\""
                        fi
                        
                        if [ -n "${S3_BUCKET_NAME}" ] && [ "${S3_BUCKET_NAME}" != "null" ]; then
                            CMD="${CMD} -var=\"s3_bucket_name=${S3_BUCKET_NAME}\""
                        fi
                        
                        echo "=========================================="
                        echo "Executing: ${CMD}"
                        echo "=========================================="
                        eval "${CMD}"
                    '''
                }
            }
        }

        stage('Terraform Destroy') {
            when { expression { env.ACTION == 'destroy' && env.DESTROY_CONFIRM == 'true' } }
            steps {
                input "FINAL CONFIRMATION: This will permanently delete all resources in ${env.ENV} environment. Proceed?"
                withCredentials([aws(credentialsId: 'd690f807-aa7f-4f36-8d44-8d0ba71dc975', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        #!/bin/bash
                        set -e
                        export AWS_DEFAULT_REGION=${AWS_REGION}
                        cd ${ENV}
                        echo "Running terragrunt destroy in $(pwd)"
                        terragrunt destroy -auto-approve
                    '''
                }
            }
        }

        stage('Validation') {
            when { expression { env.ACTION == 'create' || env.ACTION == 'update' } }
            steps {
                withCredentials([aws(credentialsId: 'd690f807-aa7f-4f36-8d44-8d0ba71dc975', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        #!/bin/bash
                        set -e
                        export AWS_DEFAULT_REGION=${AWS_REGION}
                        echo "=========================================="
                        echo "Validating resources in region: ${AWS_DEFAULT_REGION}"
                        echo "=========================================="
                        
                        cd ${ENV}
                        BUCKET_NAME=$(terragrunt output -raw s3_bucket_name 2>/dev/null || echo "")
                        
                        echo "Checking EC2 instances..."
                        aws ec2 describe-instances --filters "Name=tag:Name,Values=public-ec2" --query "Reservations[*].Instances[*].PublicIpAddress" --output text || echo "No public EC2 instances found"
                        
                        if [ -n "${BUCKET_NAME}" ]; then
                            echo "Checking S3 bucket: ${BUCKET_NAME}"
                            aws s3 ls "s3://${BUCKET_NAME}" || echo "Bucket exists but may be empty"
                        else
                            echo "S3 bucket name not available from outputs"
                        fi
                        
                        echo "=========================================="
                        echo "Validation complete for ${ENV} environment"
                        echo "VPC CIDR: ${VPC_CIDR}"
                        echo "Region: ${AWS_DEFAULT_REGION}"
                        echo "=========================================="
                    '''
                }
            }
        }
    }

    post {
        always {
            withCredentials([aws(credentialsId: 'd690f807-aa7f-4f36-8d44-8d0ba71dc975', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                sh '''
                    #!/bin/bash
                    set -e
                    export AWS_DEFAULT_REGION=${AWS_REGION}
                    echo "Running post-action in ${ENV}"
                    if [ -d "${ENV}" ]; then
                        cd ${ENV}
                        echo "Generating output in $(pwd)"
                        terragrunt output -json > cloud-receipt.json || echo "Failed to generate output"
                    else
                        echo "Warning: Directory ${ENV} does not exist, skipping output"
                    fi
                '''
            }
            archiveArtifacts artifacts: "${ENV}/cloud-receipt.json", allowEmptyArchive: true
        }
        failure {
            withCredentials([aws(credentialsId: 'd690f807-aa7f-4f36-8d44-8d0ba71dc975', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                script {
                    if (env.ACTION == 'create' || env.ACTION == 'update') {
                        sh '''
                            #!/bin/bash
                            set -e
                            export AWS_DEFAULT_REGION=${AWS_REGION}
                            echo "Running cleanup due to failure in ${ENV}"
                            if [ -d "${ENV}" ]; then
                                cd ${ENV}
                                echo "Running terragrunt destroy in $(pwd)"
                                terragrunt destroy -auto-approve || true
                            else
                                echo "Warning: Directory ${ENV} does not exist, skipping destroy"
                            fi
                        '''
                    }
                }
            }
            sh 'echo "Pipeline failed—check AWS console for partial state"'
        }
    }
}