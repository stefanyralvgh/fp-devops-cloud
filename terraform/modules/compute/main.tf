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

  # Enable detailed monitoring (free tier)
  monitoring = true

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

  # User data script (runs on first boot)
  user_data = <<-EOF
              #!/bin/bash
              # Update system
              yum update -y
              
              # Install basic tools
              yum install -y git wget curl vim
              
              # Set timezone
              timedatectl set-timezone America/Bogota
              
              # Create banner
              echo "=====================================" > /etc/motd
              echo "   Movie Analyst Bastion Host" >> /etc/motd
              echo "   Environment: ${var.environment}" >> /etc/motd
              echo "=====================================" >> /etc/motd
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