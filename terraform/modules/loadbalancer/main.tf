# Application Load Balancer
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name = var.name

  load_balancer_type = "application"

  vpc_id          = var.vpc_id
  subnets         = var.public_subnet_ids
  security_groups = [var.alb_sg_id]

  enable_deletion_protection = var.enable_deletion_protection

  # TARGET GROUP: SOLO BACKEND
  target_groups = [
    {
      name             = "${var.environment}-backend-tg"
      backend_protocol = "HTTP"
      backend_port     = var.backend_port
      target_type      = "instance"

      health_check = {
        enabled             = true
        path                = var.backend_health_check_path
        interval            = 30
        healthy_threshold   = 2
        unhealthy_threshold = 2
        timeout             = 5
        matcher             = "200-299"
      }
    }
  ]

  # HTTP LISTENER: Todo el tráfico va al backend
  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0 # Backend target group
    }
  ]

  tags = var.tags
}

# ATTACH BACKEND INSTANCES to Backend Target Group
resource "aws_lb_target_group_attachment" "backend" {
  count = length(var.backend_instance_ids)

  target_group_arn = module.alb.target_group_arns[0]
  target_id        = var.backend_instance_ids[count.index]
  port             = var.backend_port
}