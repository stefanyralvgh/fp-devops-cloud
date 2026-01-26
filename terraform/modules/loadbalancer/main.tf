module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name = var.name

  # Network
  vpc_id  = var.vpc_id
  subnets = var.public_subnet_ids

  # Security
  security_groups            = [var.alb_sg_id]
  enable_deletion_protection = var.enable_deletion_protection

  # HTTP Listener
  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  # Target Group
  target_groups = [
    {
      name             = var.target_group_name
      backend_protocol = "HTTP"
      backend_port     = var.backend_port
      target_type      = "instance"

      health_check = {
        enabled             = true
        path                = var.health_check_path
        interval            = var.health_check_interval
        healthy_threshold   = 2
        unhealthy_threshold = 2
        timeout             = 5
        matcher             = "200-399"
      }
    }
  ]

  tags = var.tags
}

# Target group attachments
resource "aws_lb_target_group_attachment" "frontend" {
  count = length(var.frontend_instance_ids)

  target_group_arn = module.alb.target_group_arns[0]
  target_id        = var.backend_instance_ids[count.index]
  port             = var.backend_port
}