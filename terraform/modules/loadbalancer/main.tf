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



  # TARGET GROUP 1: FRONTEND
  target_groups = [
    {
      name             = "${var.environment}-frontend-tg-v2"
      backend_protocol = "HTTP"
      backend_port     = var.frontend_port
      target_type      = "instance"

      health_check = {
        enabled             = true
        path                = "/"
        interval            = 30
        healthy_threshold   = 2
        unhealthy_threshold = 2
        timeout             = 5
        matcher             = "200-399"
      }
    },
    # TARGET GROUP 2: BACKEND
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

  # HTTP LISTENER con path-based routing
  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0 # Default: frontend
    }
  ]


  # LISTENER RULES: Path-based routing
  http_tcp_listener_rules = [
    # Regla 1: API paths (priority 1)
    {
      http_tcp_listener_index = 0
      priority                = 1

      actions = [{
        type               = "forward"
        target_group_index = 1  # Backend
      }]

      conditions = [{
        path_patterns = [
          "/api/*",
          "/authors",
          "/movies",
          "/reviewers",
          "/publications"
        ]
      }]
    },
    # Regla 2: Additional API paths (priority 2)
    {
      http_tcp_listener_index = 0
      priority                = 2

      actions = [{
        type               = "forward"
        target_group_index = 1  # Backend
      }]

      conditions = [{
        path_patterns = [
          "/pending",
          "/health"
        ]
      }]
    }
  ]

  tags = var.tags
}

# ATTACH FRONTEND INSTANCES to Frontend Target Group
resource "aws_lb_target_group_attachment" "frontend" {
  count = length(var.frontend_instance_ids)

  target_group_arn = module.alb.target_group_arns[0] # Frontend TG
  target_id        = var.frontend_instance_ids[count.index]
  port             = var.frontend_port
}

# ATTACH BACKEND INSTANCES to Backend Target Group
resource "aws_lb_target_group_attachment" "backend" {
  count = length(var.backend_instance_ids)

  target_group_arn = module.alb.target_group_arns[1] # Backend TG
  target_id        = var.backend_instance_ids[count.index]
  port             = var.backend_port
}