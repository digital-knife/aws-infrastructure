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
        ENV = "${params.environment ?: 'dev'}"
        ACTION = "${params.action}"
        DESTROY_CONFIRM = "${params.destroy}"
        
        // Convert Jenkins params to TF_VAR_ environment variables
        // These automatically get picked up by Terraform/Terragrunt
        TF_VAR_aws_region = "${params.aws_region}"
        TF_VAR_vpc_cidr = ""  // Set dynamically in Set ENV Default stage
        TF_VAR_vpc_name = "${params.vpc_name}"
        TF_VAR_project_name = "${params.vpc_name != '' && params.vpc_name != 'null' ? params.vpc_name : 'aws-infrastructure'}"
        TF_VAR_vpc_tag = "${params.vpc_tag}"
        TF_VAR_public_subnet_cidr = "${params.public_subnet_cidr}"
        TF_VAR_private_subnet_cidr = "${params.private_subnet_cidr}"
        TF_VAR_instance_type = "${params.instance_type}"
        TF_VAR_s3_bucket_name = "${params.s3_bucket_name}"
    }

    parameters {
        choice(
            name: 'environment', 
            choices: ['dev', 'prod'], 
            description: '''Environment Selection (CIDR auto-assigned):
            • dev VPC CIDR: 10.0.0.0/16 (must use 10.0.x.x)
            • prod VPC CIDR: 10.1.0.0/16 (must use 10.1.x.x)'''
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
            • Leave empty to use default(dev-vpc or prod-vpc)'''
        )
        string(
            name: 'vpc_tag', 
            defaultValue: '', 
            description: '''Additional VPC Tag (optional):
            • Leave empty for standard tagging only'''
        )
        string(
            name: 'public_subnet_cidr', 
            defaultValue: '', 
            description: '''Public Subnet CIDR (optional):
            • Leave empty for auto-assignment
            • dev:  Must be within 10.0.0.0/16
            • prod: Must be within 10.1.0.0/16
            • Job will FAIL if subnet is outside VPC range'''
        )
        string(
            name: 'private_subnet_cidr', 
            defaultValue: '', 
            description: '''Private Subnet CIDR (optional):
            • Leave empty for auto-assignment
            • dev:  Must be within 10.0.0.0/16 
            • prod: Must be within 10.1.0.0/16 
            • Job will FAIL if subnet is outside VPC range'''
        )
        choice(
            name: 'instance_type', 
            choices: ['', 't3.micro', 't3.small'], 
            description: '''EC2 Instance Type:
            • Leave empty to use default (dev: t3.micro, prod: t3.small)
            • t3.micro: 2 vCPU, 1GB RAM
            • t3.small: 2 vCPU, 2GB RAM'''
        )
        string(
            name: 's3_bucket_name', 
            defaultValue: '', 
            description: '''S3 Bucket Name (optional):
            • Leave empty to use default
            • Must be globally unique across ALL AWS accounts
            • Use lowercase, numbers, and hyphens only'''
        )
        choice(
            name: 'action', 
            choices: ['create', 'update', 'destroy'], 
            description: '''Action to Perform:
            • Create:  Provision new infrastructure
            • Update:  Modify existing infrastructure
            • Destroy: DELETE all resources (requires confirmation)'''
        )
        booleanParam(
            name: 'destroy', 
            defaultValue: false, 
            description: '''DESTROY CONFIRMATION (required for destroy):
            • DESTROYING CANNOT BE UNDONE 
            • all data will be PERMANENTLY deleted'''
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
                        env.TF_VAR_vpc_cidr = '10.0.0.0/16'
                    } else if (env.ENV == 'prod') {
                        env.VPC_CIDR = '10.1.0.0/16'
                        env.VPC_CIDR_PREFIX = '10.1'
                        env.TF_VAR_vpc_cidr = '10.1.0.0/16'
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
                        
                        echo "=========================================="
                        echo "Running terragrunt plan with variables:"
                        echo "VPC Name: ${TF_VAR_vpc_name}"
                        echo "Project Name: ${TF_VAR_project_name}"
                        echo "VPC Tag: ${TF_VAR_vpc_tag}"
                        echo "VPC CIDR: ${TF_VAR_vpc_cidr}"
                        echo "S3 Bucket: ${TF_VAR_s3_bucket_name}"
                        echo "=========================================="
                        
                        terragrunt plan
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
                        
                        echo "Refreshing Terraform state..."
                        terragrunt refresh
                        
                        echo "=========================================="
                        echo "Applying Terraform configuration..."
                        echo "VPC Name: ${TF_VAR_vpc_name}"
                        echo "Project Name: ${TF_VAR_project_name}"
                        echo "VPC Tag: ${TF_VAR_vpc_tag}"
                        echo "=========================================="
                        
                        terragrunt apply -auto-approve
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

        stage('Post-Deployment Validation') {
            when { expression { env.ACTION == 'create' || env.ACTION == 'update' } }
            steps {
                withCredentials([aws(credentialsId: 'd690f807-aa7f-4f36-8d44-8d0ba71dc975', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        #!/bin/bash
                        set -e
                        export AWS_DEFAULT_REGION=${AWS_REGION}
                        cd ${ENV}
                        
                        echo "Running comprehensive post-deployment health checks..."
                        chmod +x ../health_check.sh
                        ../health_check.sh "${ENV}" "${AWS_REGION}"
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