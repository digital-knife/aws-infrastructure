# ============================================================================
# BASTION HOST - SSH jump box for administrative access
# ============================================================================

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.bastion.id]

  # Enable detailed monitoring
  monitoring = true

  # User data for bastion setup
  user_data = <<-EOF
              #!/bin/bash
              yum install -y amazon-ssm-agent htop vim wget curl
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent
              
              echo "Bastion host ready - Environment: ${var.environment}" > /etc/motd
              
              # Run system updates in background (non-blocking)
              yum update -y &
              EOF

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-bastion"
      Role = "bastion"
      Tier = "public"
    }
  )
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

  # Enable detailed monitoring
  monitoring = true

  # User data for web server setup
  user_data = <<-EOF
              #!/bin/bash
              # Install Apache and SSM FIRST (fast - no updates yet)
              sudo yum install -y httpd amazon-ssm-agent
              
              # Start Apache IMMEDIATELY so health checks pass
              systemctl start httpd
              systemctl enable httpd
              
              # Start and enable SSM agent
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent
              
              # Create index page with instance info
              INSTANCE_ID=$(ec2-metadata --instance-id | cut -d " " -f 2)
              AZ=$(ec2-metadata --availability-zone | cut -d " " -f 2)
              
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
                          <strong>Instance ID:</strong> INSTANCE_ID<br>
                          <strong>Availability Zone:</strong> AZ<br>
                          <strong>Environment:</strong> ${var.environment}<br>
                          <strong>Server:</strong> Web-1
                      </div>
                      <p>Traffic is being load balanced by ALB across multiple availability zones.</p>
                  </div>
              </body>
              </html>
HTML
              
              # Replace placeholders
              sed -i "s/INSTANCE_ID/$INSTANCE_ID/g" /var/www/html/index.html
              sed -i "s/AZ/$AZ/g" /var/www/html/index.html
              
              # Run system updates in background (non-blocking)
              yum update -y &
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

  # Enable detailed monitoring
  monitoring = true

  # User data for web server setup
  user_data = <<-EOF
              #!/bin/bash
              # Install Apache and SSM FIRST (fast - no updates yet)
              yum install -y httpd amazon-ssm-agent
              
              # Start Apache IMMEDIATELY so health checks pass
              systemctl start httpd
              systemctl enable httpd
              
              # Start and enable SSM agent
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent
              
              # Create index page with instance info
              INSTANCE_ID=$(ec2-metadata --instance-id | cut -d " " -f 2)
              AZ=$(ec2-metadata --availability-zone | cut -d " " -f 2)
              
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
                          <strong>Instance ID:</strong> INSTANCE_ID<br>
                          <strong>Availability Zone:</strong> AZ<br>
                          <strong>Environment:</strong> ${var.environment}<br>
                          <strong>Server:</strong> Web-2
                      </div>
                      <p>Traffic is being load balanced by ALB across multiple availability zones.</p>
                  </div>
              </body>
              </html>
HTML
              
              # Replace placeholders
              sed -i "s/INSTANCE_ID/$INSTANCE_ID/g" /var/www/html/index.html
              sed -i "s/AZ/$AZ/g" /var/www/html/index.html
              
              # Run system updates in background (non-blocking)
              yum update -y &
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
