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
              exec > /tmp/user-data.log 2>&1
              set -x
              
              echo "Waiting for internet..."
              until ping -c 1 8.8.8.8 &> /dev/null; do
                sleep 5
              done
              echo "Internet ready"
              
              yum install -y amazon-ssm-agent htop vim wget curl
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent
              
              echo "Bastion ready - ${var.environment}" > /etc/motd
              
              nohup yum update -y > /tmp/yum-update.log 2>&1 &
              echo "User data complete"
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
              exec > /var/log/user-data.log 2>&1
              set -ex
              
              echo "=== Web Server 1 Startup: $(date) ==="
              
              # Wait for internet
              echo "Waiting for internet..."
              for i in {1..60}; do
                if ping -c 1 8.8.8.8 &> /dev/null; then
                  echo "Internet connected"
                  break
                fi
                sleep 5
              done
              
              # Install httpd and SSM
              echo "Installing httpd and amazon-ssm-agent..."
              yum install -y httpd amazon-ssm-agent
              
              # Start httpd
              echo "Starting httpd..."
              systemctl start httpd
              systemctl enable httpd
              
              # Verify httpd is running
              if systemctl is-active httpd; then
                echo "✓ httpd is running"
              else
                echo "✗ httpd failed to start"
                systemctl status httpd
                exit 1
              fi
              
              # Start SSM
              systemctl start amazon-ssm-agent
              systemctl enable amazon-ssm-agent
              
              # Create index.html
              echo "Creating index.html..."
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
              
              # Set permissions
              chmod 644 /var/www/html/index.html
              chown apache:apache /var/www/html/index.html
              
              # Get metadata
              INSTANCE_ID=$(ec2-metadata --instance-id 2>/dev/null | cut -d " " -f 2)
              AZ=$(ec2-metadata --availability-zone 2>/dev/null | cut -d " " -f 2)
              INSTANCE_ID=$${INSTANCE_ID:-unknown}
              AZ=$${AZ:-unknown}
              
              # Update index.html
              sed -i "s/__INSTANCE_ID__/$INSTANCE_ID/g" /var/www/html/index.html
              sed -i "s/__AZ__/$AZ/g" /var/www/html/index.html
              
              # Restart httpd
              systemctl restart httpd
              
              # Verify index.html exists
              if [ -f /var/www/html/index.html ]; then
                echo "✓ index.html created"
                ls -la /var/www/html/index.html
              else
                echo "✗ ERROR: index.html missing!"
                exit 1
              fi
              
              # Test httpd response
              sleep 2
              if curl -s http://localhost/ | grep -q "Web Server 1"; then
                echo "✓ httpd responding correctly"
              else
                echo "✗ httpd not responding"
                curl -v http://localhost/ || true
              fi
              
              echo "=== CRITICAL SETUP COMPLETE ==="
              
              # Install CloudWatch (non-critical)
              echo "Installing CloudWatch agent..."
              yum install -y amazon-cloudwatch-agent || echo "WARNING: CloudWatch install failed"
              
              # Create config directory
              mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
              
              # Configure CloudWatch
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
              if [ -f /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl ]; then
                /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                  -a fetch-config -m ec2 -s \
                  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json || echo "WARNING: CloudWatch start failed"
              fi
              
              # Create metrics script
              cat > /usr/local/bin/custom-metrics.sh << 'METRICS'
#!/bin/bash
INSTANCE_ID=$(ec2-metadata --instance-id 2>/dev/null | cut -d " " -f 2)
REGION=$(ec2-metadata --availability-zone 2>/dev/null | cut -d " " -f 2 | sed 's/.$//')

INSTANCE_ID=$${INSTANCE_ID:-unknown}
REGION=$${REGION:-${var.aws_region}}

HTTPD_STATUS=$(systemctl is-active httpd &>/dev/null && echo 1 || echo 0)
PING_STATUS=$(ping -c 1 8.8.8.8 &>/dev/null && echo 1 || echo 0)

aws cloudwatch put-metric-data --region $REGION \
  --namespace "CustomMetrics/${var.environment}" \
  --metric-name httpd_status --value $HTTPD_STATUS \
  --dimensions InstanceId=$INSTANCE_ID 2>/dev/null || true

aws cloudwatch put-metric-data --region $REGION \
  --namespace "CustomMetrics/${var.environment}" \
  --metric-name internet_connectivity --value $PING_STATUS \
  --dimensions InstanceId=$INSTANCE_ID 2>/dev/null || true
METRICS
              
              chmod +x /usr/local/bin/custom-metrics.sh
              
              # Add to crontab
              (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/custom-metrics.sh") | crontab - || echo "WARNING: Cron failed"
              
              # Background yum update
              nohup yum update -y > /tmp/yum-update.log 2>&1 &
              
              echo "=== Web Server 1 Complete: $(date) ==="
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
              exec > /var/log/user-data.log 2>&1
              set -ex
              
              echo "=== Web Server 2 Startup: $(date) ==="
              
              # Wait for internet
              echo "Waiting for internet..."
              for i in {1..60}; do
                if ping -c 1 8.8.8.8 &> /dev/null; then
                  echo "Internet connected"
                  break
                fi
                sleep 5
              done
              
              # Install httpd and SSM
              echo "Installing httpd and amazon-ssm-agent..."
              yum install -y httpd amazon-ssm-agent
              
              # Start httpd
              echo "Starting httpd..."
              systemctl start httpd
              systemctl enable httpd
              
              # Verify httpd is running
              if systemctl is-active httpd; then
                echo "✓ httpd is running"
              else
                echo "✗ httpd failed to start"
                systemctl status httpd
                exit 1
              fi
              
              # Start SSM
              systemctl start amazon-ssm-agent
              systemctl enable amazon-ssm-agent
              
              # Create index.html
              echo "Creating index.html..."
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
              
              # Set permissions
              chmod 644 /var/www/html/index.html
              chown apache:apache /var/www/html/index.html
              
              # Get metadata
              INSTANCE_ID=$(ec2-metadata --instance-id 2>/dev/null | cut -d " " -f 2)
              AZ=$(ec2-metadata --availability-zone 2>/dev/null | cut -d " " -f 2)
              INSTANCE_ID=$${INSTANCE_ID:-unknown}
              AZ=$${AZ:-unknown}
              
              # Update index.html
              sed -i "s/__INSTANCE_ID__/$INSTANCE_ID/g" /var/www/html/index.html
              sed -i "s/__AZ__/$AZ/g" /var/www/html/index.html
              
              # Restart httpd
              systemctl restart httpd
              
              # Verify index.html exists
              if [ -f /var/www/html/index.html ]; then
                echo "✓ index.html created"
                ls -la /var/www/html/index.html
              else
                echo "✗ ERROR: index.html missing!"
                exit 1
              fi
              
              # Test httpd response
              sleep 2
              if curl -s http://localhost/ | grep -q "Web Server 2"; then
                echo "✓ httpd responding correctly"
              else
                echo "✗ httpd not responding"
                curl -v http://localhost/ || true
              fi
              
              echo "=== CRITICAL SETUP COMPLETE ==="
              
              # Install CloudWatch (non-critical)
              echo "Installing CloudWatch agent..."
              yum install -y amazon-cloudwatch-agent || echo "WARNING: CloudWatch install failed"
              
              # Create config directory
              mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
              
              # Configure CloudWatch
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
              if [ -f /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl ]; then
                /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                  -a fetch-config -m ec2 -s \
                  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json || echo "WARNING: CloudWatch start failed"
              fi
              
              # Create metrics script
              cat > /usr/local/bin/custom-metrics.sh << 'METRICS'
#!/bin/bash
INSTANCE_ID=$(ec2-metadata --instance-id 2>/dev/null | cut -d " " -f 2)
REGION=$(ec2-metadata --availability-zone 2>/dev/null | cut -d " " -f 2 | sed 's/.$//')

INSTANCE_ID=$${INSTANCE_ID:-unknown}
REGION=$${REGION:-${var.aws_region}}

HTTPD_STATUS=$(systemctl is-active httpd &>/dev/null && echo 1 || echo 0)
PING_STATUS=$(ping -c 1 8.8.8.8 &>/dev/null && echo 1 || echo 0)

aws cloudwatch put-metric-data --region $REGION \
  --namespace "CustomMetrics/${var.environment}" \
  --metric-name httpd_status --value $HTTPD_STATUS \
  --dimensions InstanceId=$INSTANCE_ID 2>/dev/null || true

aws cloudwatch put-metric-data --region $REGION \
  --namespace "CustomMetrics/${var.environment}" \
  --metric-name internet_connectivity --value $PING_STATUS \
  --dimensions InstanceId=$INSTANCE_ID 2>/dev/null || true
METRICS
              
              chmod +x /usr/local/bin/custom-metrics.sh
              
              # Add to crontab
              (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/custom-metrics.sh") | crontab - || echo "WARNING: Cron failed"
              
              # Background yum update
              nohup yum update -y > /tmp/yum-update.log 2>&1 &
              
              echo "=== Web Server 2 Complete: $(date) ==="
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
