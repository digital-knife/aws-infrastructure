# ============================================================================
# BASTION HOST - SSH jump box for administrative access
# ============================================================================

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.bastion.id]

  monitoring = true

  user_data = <<-EOF
              #!/bin/bash
              echo "Waiting for internet..." > /tmp/user-data.log
              until ping -c 1 8.8.8.8 &> /dev/null; do
                sleep 5
              done
              echo "Internet ready" >> /tmp/user-data.log
              
              yum install -y amazon-ssm-agent htop vim wget curl >> /tmp/user-data.log 2>&1
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent
              
              echo "Bastion ready - ${var.environment}" > /etc/motd
              
              yum update -y &
              echo "User data complete" >> /tmp/user-data.log
              EOF

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-bastion"
      Role = "bastion"
      Tier = "public"
    }
  )

  depends_on = [aws_nat_gateway.main]
}

# ============================================================================
# WEB SERVER 1 - Private subnet AZ1
# ============================================================================

resource "aws_instance" "web_1" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  subnet_id              = aws_subnet.private_1.id
  vpc_security_group_ids = [aws_security_group.web.id]

  monitoring = true

  user_data = <<-EOF
              #!/bin/bash
              set -x  # Debug mode
              exec > >(tee /var/log/user-data.log)
              exec 2>&1
              
              echo "=== Starting user_data for Web Server 1 at $(date) ==="
              
              # Wait for internet connectivity via NAT Gateway
              echo "Waiting for internet connectivity..."
              until ping -c 1 8.8.8.8 &> /dev/null; do
                echo "Still waiting for internet... $(date)"
                sleep 5
              done
              echo "Internet connectivity established at $(date)"
              
              # Install httpd and SSM agent FIRST
              echo "Installing httpd and amazon-ssm-agent..."
              yum install -y httpd amazon-ssm-agent
              
              # Start services immediately
              echo "Starting httpd service..."
              systemctl start httpd
              systemctl enable httpd
              
              echo "Starting SSM agent..."
              systemctl start amazon-ssm-agent
              systemctl enable amazon-ssm-agent
              
              # CREATE INDEX.HTML IMMEDIATELY - Critical for ALB health checks
              echo "Creating index.html for ALB health checks..."
              cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Web Server 1</title>
    <style>
        body { font-family: Arial; margin: 40px; background: #f0f0f0; }
        .container { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #232f3e; }
        .info { background: #e8f4f8; padding: 10px; border-left: 4px solid #0073bb; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>✅ Web Server 1 - Healthy</h1>
        <div class="info">
            <strong>Instance ID:</strong> __INSTANCE_ID__<br>
            <strong>Availability Zone:</strong> __AZ__<br>
            <strong>Environment:</strong> ${var.environment}<br>
            <strong>Server:</strong> Web-1
        </div>
        <p>Traffic is being load balanced by ALB across multiple availability zones.</p>
    </div>
</body>
</html>
HTML
              
              # Set proper permissions for Apache
              echo "Setting file permissions..."
              chmod 644 /var/www/html/index.html
              chown apache:apache /var/www/html/index.html
              
              # Get instance metadata and update index.html
              echo "Fetching instance metadata..."
              INSTANCE_ID=$(ec2-metadata --instance-id 2>/dev/null | cut -d " " -f 2 || echo "unknown")
              AZ=$(ec2-metadata --availability-zone 2>/dev/null | cut -d " " -f 2 || echo "unknown")
              
              echo "Updating index.html with Instance ID: $INSTANCE_ID, AZ: $AZ"
              sed -i "s/__INSTANCE_ID__/$INSTANCE_ID/g" /var/www/html/index.html
              sed -i "s/__AZ__/$AZ/g" /var/www/html/index.html
              
              # Restart httpd to ensure it's serving the new content
              echo "Restarting httpd to serve updated content..."
              systemctl restart httpd
              
              # Verify index.html was created successfully
              echo "Verifying index.html creation..."
              if [ -f /var/www/html/index.html ]; then
                echo "✓ index.html exists"
                echo "Content preview:"
                head -5 /var/www/html/index.html
              else
                echo "✗ ERROR: index.html was not created!"
              fi
              
              # Test local httpd response
              echo "Testing local httpd response..."
              curl -s http://localhost/ | head -2 || echo "ERROR: httpd not responding"
              
              echo "=== Critical setup complete. ALB health checks should pass. ==="
              
              # NOW install CloudWatch agent (non-critical, failures won't break health checks)
              echo "Installing CloudWatch agent (non-critical)..."
              yum install -y amazon-cloudwatch-agent || {
                echo "WARNING: CloudWatch agent installation failed, but continuing..."
              }
              
              # Configure CloudWatch agent
              cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json << 'CWCONFIG'
              {
                "metrics": {
                  "namespace": "CustomMetrics/${var.environment}",
                  "metrics_collected": {
                    "cpu": {
                      "measurement": [{"name": "cpu_usage_idle", "rename": "CPU_IDLE", "unit": "Percent"}],
                      "totalcpu": false
                    },
                    "disk": {
                      "measurement": [{"name": "used_percent", "rename": "DISK_USED", "unit": "Percent"}],
                      "resources": ["/"]
                    },
                    "mem": {
                      "measurement": [{"name": "mem_used_percent", "rename": "MEMORY_USED", "unit": "Percent"}]
                    }
                  }
                }
              }
CWCONFIG
              
              # Start CloudWatch agent
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                -a fetch-config -m ec2 -s \
                -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json || {
                echo "WARNING: CloudWatch agent start failed"
              }
              
              # Create custom metrics script
              cat > /usr/local/bin/custom-metrics.sh << 'METRICS'
#!/bin/bash
INSTANCE_ID=$(ec2-metadata --instance-id | cut -d " " -f 2)
REGION=$(ec2-metadata --availability-zone | sed 's/[a-z]$//')

# Check httpd service
HTTPD_STATUS=$(systemctl is-active httpd &>/dev/null && echo 1 || echo 0)

# Days since last yum update
LAST_UPDATE=$(rpm -qa --last | head -1 | awk '{print $3,$4,$5}')
DAYS_SINCE=$(( ($(date +%s) - $(date -d "$LAST_UPDATE" +%s)) / 86400 ))

# Ping test
PING_STATUS=$(ping -c 1 8.8.8.8 &>/dev/null && echo 1 || echo 0)

# Push to CloudWatch
aws cloudwatch put-metric-data --region $REGION \
  --namespace "CustomMetrics/${var.environment}" \
  --metric-name httpd_status --value $HTTPD_STATUS --dimensions InstanceId=$INSTANCE_ID
  
aws cloudwatch put-metric-data --region $REGION \
  --namespace "CustomMetrics/${var.environment}" \
  --metric-name days_since_yum_update --value $DAYS_SINCE --dimensions InstanceId=$INSTANCE_ID
  
aws cloudwatch put-metric-data --region $REGION \
  --namespace "CustomMetrics/${var.environment}" \
  --metric-name internet_connectivity --value $PING_STATUS --dimensions InstanceId=$INSTANCE_ID
METRICS
              
              chmod +x /usr/local/bin/custom-metrics.sh
              echo "*/5 * * * * /usr/local/bin/custom-metrics.sh" | crontab - || echo "WARNING: Cron setup failed"
              
              # Background yum update (non-blocking)
              echo "Starting background yum update..."
              nohup yum update -y > /tmp/yum-update.log 2>&1 &
              
              echo "=== User data complete for Web Server 1 at $(date) ==="
              echo "=== All services should be healthy and ready ==="
              EOF

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-web-1"
      Role = "web"
      Tier = "private"
      AZ   = data.aws_availability_zones.available.names[0]
    }
  )

  depends_on = [aws_nat_gateway.main]
}

# ============================================================================
# WEB SERVER 2 - Private subnet AZ2
# ============================================================================

resource "aws_instance" "web_2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  subnet_id              = aws_subnet.private_2.id
  vpc_security_group_ids = [aws_security_group.web.id]

  monitoring = true

  user_data = <<-EOF
              #!/bin/bash
              set -x  # Debug mode
              exec > >(tee /var/log/user-data.log)
              exec 2>&1
              
              echo "=== Starting user_data for Web Server 2 at $(date) ==="
              
              # Wait for internet connectivity via NAT Gateway
              echo "Waiting for internet connectivity..."
              until ping -c 1 8.8.8.8 &> /dev/null; do
                echo "Still waiting for internet... $(date)"
                sleep 5
              done
              echo "Internet connectivity established at $(date)"
              
              # Install httpd and SSM agent FIRST
              echo "Installing httpd and amazon-ssm-agent..."
              yum install -y httpd amazon-ssm-agent
              
              # Start services immediately
              echo "Starting httpd service..."
              systemctl start httpd
              systemctl enable httpd
              
              echo "Starting SSM agent..."
              systemctl start amazon-ssm-agent
              systemctl enable amazon-ssm-agent
              
              # CREATE INDEX.HTML IMMEDIATELY - Critical for ALB health checks
              echo "Creating index.html for ALB health checks..."
              cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Web Server 2</title>
    <style>
        body { font-family: Arial; margin: 40px; background: #f0f0f0; }
        .container { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #232f3e; }
        .info { background: #e8f4f8; padding: 10px; border-left: 4px solid #0073bb; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>✅ Web Server 2 - Healthy</h1>
        <div class="info">
            <strong>Instance ID:</strong> __INSTANCE_ID__<br>
            <strong>Availability Zone:</strong> __AZ__<br>
            <strong>Environment:</strong> ${var.environment}<br>
            <strong>Server:</strong> Web-2
        </div>
        <p>Traffic is being load balanced by ALB across multiple availability zones.</p>
    </div>
</body>
</html>
HTML
              
              # Set proper permissions for Apache
              echo "Setting file permissions..."
              chmod 644 /var/www/html/index.html
              chown apache:apache /var/www/html/index.html
              
              # Get instance metadata and update index.html
              echo "Fetching instance metadata..."
              INSTANCE_ID=$(ec2-metadata --instance-id 2>/dev/null | cut -d " " -f 2 || echo "unknown")
              AZ=$(ec2-metadata --availability-zone 2>/dev/null | cut -d " " -f 2 || echo "unknown")
              
              echo "Updating index.html with Instance ID: $INSTANCE_ID, AZ: $AZ"
              sed -i "s/__INSTANCE_ID__/$INSTANCE_ID/g" /var/www/html/index.html
              sed -i "s/__AZ__/$AZ/g" /var/www/html/index.html
              
              # Restart httpd to ensure it's serving the new content
              echo "Restarting httpd to serve updated content..."
              systemctl restart httpd
              
              # Verify index.html was created successfully
              echo "Verifying index.html creation..."
              if [ -f /var/www/html/index.html ]; then
                echo "✓ index.html exists"
                echo "Content preview:"
                head -5 /var/www/html/index.html
              else
                echo "✗ ERROR: index.html was not created!"
              fi
              
              # Test local httpd response
              echo "Testing local httpd response..."
              curl -s http://localhost/ | head -2 || echo "ERROR: httpd not responding"
              
              echo "=== Critical setup complete. ALB health checks should pass. ==="
              
              # NOW install CloudWatch agent (non-critical, failures won't break health checks)
              echo "Installing CloudWatch agent (non-critical)..."
              yum install -y amazon-cloudwatch-agent || {
                echo "WARNING: CloudWatch agent installation failed, but continuing..."
              }
              
              # Configure CloudWatch agent
              cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json << 'CWCONFIG'
              {
                "metrics": {
                  "namespace": "CustomMetrics/${var.environment}",
                  "metrics_collected": {
                    "cpu": {
                      "measurement": [{"name": "cpu_usage_idle", "rename": "CPU_IDLE", "unit": "Percent"}],
                      "totalcpu": false
                    },
                    "disk": {
                      "measurement": [{"name": "used_percent", "rename": "DISK_USED", "unit": "Percent"}],
                      "resources": ["/"]
                    },
                    "mem": {
                      "measurement": [{"name": "mem_used_percent", "rename": "MEMORY_USED", "unit": "Percent"}]
                    }
                  }
                }
              }
CWCONFIG
              
              # Start CloudWatch agent
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                -a fetch-config -m ec2 -s \
                -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json || {
                echo "WARNING: CloudWatch agent start failed"
              }
              
              # Create custom metrics script
              cat > /usr/local/bin/custom-metrics.sh << 'METRICS'
#!/bin/bash
INSTANCE_ID=$(ec2-metadata --instance-id | cut -d " " -f 2)
REGION=$(ec2-metadata --availability-zone | sed 's/[a-z]$//')

# Check httpd service
HTTPD_STATUS=$(systemctl is-active httpd &>/dev/null && echo 1 || echo 0)

# Days since last yum update
LAST_UPDATE=$(rpm -qa --last | head -1 | awk '{print $3,$4,$5}')
DAYS_SINCE=$(( ($(date +%s) - $(date -d "$LAST_UPDATE" +%s)) / 86400 ))

# Ping test
PING_STATUS=$(ping -c 1 8.8.8.8 &>/dev/null && echo 1 || echo 0)

# Push to CloudWatch
aws cloudwatch put-metric-data --region $REGION \
  --namespace "CustomMetrics/${var.environment}" \
  --metric-name httpd_status --value $HTTPD_STATUS --dimensions InstanceId=$INSTANCE_ID
  
aws cloudwatch put-metric-data --region $REGION \
  --namespace "CustomMetrics/${var.environment}" \
  --metric-name days_since_yum_update --value $DAYS_SINCE --dimensions InstanceId=$INSTANCE_ID
  
aws cloudwatch put-metric-data --region $REGION \
  --namespace "CustomMetrics/${var.environment}" \
  --metric-name internet_connectivity --value $PING_STATUS --dimensions InstanceId=$INSTANCE_ID
METRICS
              
              chmod +x /usr/local/bin/custom-metrics.sh
              echo "*/5 * * * * /usr/local/bin/custom-metrics.sh" | crontab - || echo "WARNING: Cron setup failed"
              
              # Background yum update (non-blocking)
              echo "Starting background yum update..."
              nohup yum update -y > /tmp/yum-update.log 2>&1 &
              
              echo "=== User data complete for Web Server 2 at $(date) ==="
              echo "=== All services should be healthy and ready ==="
              EOF

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-web-2"
      Role = "web"
      Tier = "private"
      AZ   = data.aws_availability_zones.available.names[1]
    }
  )

  depends_on = [aws_nat_gateway.main]
}

# ============================================================================
# DATA SOURCE - Latest Amazon Linux 2 AMI
# ============================================================================

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
