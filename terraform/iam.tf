# IAM ROLE FOR BACKEND INSTANCES

resource "aws_iam_role" "backend" {
  name = "${terraform.workspace}-backend-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${terraform.workspace}-backend-role"
    Environment = terraform.workspace
    ManagedBy   = "Terraform"
  }
}


# IAM POLICIES FOR BACKEND

resource "aws_iam_role_policy" "backend_cloudwatch" {
  name = "cloudwatch-logs"
  role = aws_iam_role.backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "backend_ssm" {
  name = "ssm-access"
  role = aws_iam_role.backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/movie-analyst/${terraform.workspace}/*"
      }
    ]
  })
}


# IAM INSTANCE PROFILE

resource "aws_iam_instance_profile" "backend" {
  name = "${terraform.workspace}-backend-profile"
  role = aws_iam_role.backend.name

  tags = {
    Name        = "${terraform.workspace}-backend-profile"
    Environment = terraform.workspace
    ManagedBy   = "Terraform"
  }
}