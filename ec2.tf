# EC2 Instance in Public Subnet
resource "aws_instance" "public" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion.id]

  # Enable detailed monitoring
  monitoring = true

  # User data for initial setup
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y amazon-cloudwatch-agent
              EOF

  tags = merge(
    local.common_tags,
    {
      Name = "public-ec2"
    }
  )
}

# EC2 Instance in Private Subnet
resource "aws_instance" "private" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.web.id]

  # Enable detailed monitoring
  monitoring = true

  # User data for web server setup
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd amazon-cloudwatch-agent
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Private Web Server</h1>" > /var/www/html/index.html
              EOF

  tags = merge(
    local.common_tags,
    {
      Name = "private-ec2"
    }
  )
}

# Data source to get latest Amazon Linux 2 AMI
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
