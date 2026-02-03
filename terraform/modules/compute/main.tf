# DATA SOURCE: Latest Amazon Linux 2 AMI

data "aws_ami" "amazon_linux_2" {
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


# BASTION HOST

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.bastion_instance_type
  key_name               = var.key_name
  subnet_id              = var.public_subnet_ids[0] # First public subnet
  vpc_security_group_ids = [var.bastion_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  # Enable detailed monitoring (free tier)
  monitoring = var.enable_detailed_monitoring

  # Root volume configuration
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8 # GB 
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.environment}-bastion-root-volume"
    }
  }

  user_data = <<-EOF
  #!/bin/bash
  set -e

  # Log básico
  exec > /var/log/user-data.log 2>&1

  # Update system
  yum update -y

  # Base tools
  yum install -y \
    python3 \
    python3-pip \
    git \
    wget \
    curl \
    vim \
    jq

  # Upgrade pip (compatible)
  python3 -m pip install --upgrade "pip<23"

  # Install Ansible LEGACY compatible with Python 3.7
  python3 -m pip install "ansible<2.12"

  # Make ansible available system-wide
  ln -s /usr/local/bin/ansible /usr/bin/ansible
  ln -s /usr/local/bin/ansible-playbook /usr/bin/ansible-playbook

  # Verify
  ansible --version
  ansible-playbook --version

  # Timezone
  timedatectl set-timezone America/Bogota

  # Banner
  cat > /etc/motd <<EOF
  =====================================
    Movie Analyst Bastion Host
    Environment: ${var.environment}
  =====================================
  EOF





  tags = {
    Name        = "${var.environment}-bastion-host"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Role        = "Bastion"
  }
}


# ELASTIC IP FOR BASTION

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"

  tags = {
    Name        = "${var.environment}-bastion-eip"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  # Ensure instance is created before EIP
  depends_on = [aws_instance.bastion]
}


# BACKEND INSTANCES

resource "aws_instance" "backend" {
  count = var.backend_instance_count

  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.backend_instance_type
  key_name               = var.key_name
  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids = [var.backend_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.backend.name


  # Enable detailed monitoring
  monitoring = var.enable_detailed_monitoring

  # Root volume configuration
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.environment}-backend-${count.index + 1}-root-volume"
    }
  }

  # User data script
  user_data = <<-EOF
              #!/bin/bash
              # Update system
              yum update -y

              
              # Install development tools
              yum groupinstall -y "Development Tools"
              yum install -y git wget curl vim

              # Set custom hostname
              hostnamectl set-hostname backend-${count.index + 1}-${var.environment}
              echo "127.0.0.1 backend-${count.index + 1}-${var.environment}" >> /etc/hosts
              
              # Set timezone
              timedatectl set-timezone America/Bogota
              
              # Create application directory
              mkdir -p /opt/movie-analyst
              
              # Create banner
              echo "=====================================" > /etc/motd
              echo "   Movie Analyst Backend Server" >> /etc/motd
              echo "   Instance: ${count.index + 1}" >> /etc/motd
              echo "   Environment: ${var.environment}" >> /etc/motd
              echo "=====================================" >> /etc/motd
              EOF

  tags = {
    Name        = "${var.environment}-backend-${count.index + 1}"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Role        = "Backend"
    Tier        = "Application"
  }
}


# FRONTEND INSTANCES


resource "aws_instance" "frontend" {
  count = var.frontend_instance_count

  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.frontend_instance_type
  key_name                    = var.key_name
  subnet_id                   = var.public_subnet_ids[count.index % length(var.public_subnet_ids)]
  vpc_security_group_ids      = [var.frontend_sg_id]
  iam_instance_profile        = aws_iam_instance_profile.frontend.name
  associate_public_ip_address = true # Frontend needs public IP

  # Enable detailed monitoring based on environment
  monitoring = var.enable_detailed_monitoring

  # Root volume configuration
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.environment}-frontend-${count.index + 1}-root-volume"
    }
  }

  # User data script
  user_data = <<-EOF
              #!/bin/bash
              # Log everything for debugging
              exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
              
              # Update system
              yum update -y
              
              # Install basic tools
              yum install -y git wget curl vim
              
              # Install Nginx using amazon-linux-extras
              amazon-linux-extras install nginx1 -y
              
              # Set timezone
              timedatectl set-timezone America/Bogota

                # Set custom hostname
                hostnamectl set-hostname frontend-${count.index + 1}-${var.environment}
                echo "127.0.0.1 frontend-${count.index + 1}-${var.environment}" >> /etc/hosts
              
              # Create application directory
              mkdir -p /var/www/movie-analyst
              chown -R nginx:nginx /var/www/movie-analyst
              
              # Enable and start nginx
              systemctl enable nginx
              systemctl start nginx
              
              # Create banner
              cat > /etc/motd <<'BANNER'
              =====================================
              Movie Analyst Frontend Server
              Instance: ${count.index + 1}
              Environment: ${var.environment}
              =====================================
              BANNER

              EOF

  tags = {
    Name        = "${var.environment}-frontend-${count.index + 1}"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Role        = "Frontend"
    Tier        = "Web"
  }
}