###############################################################################
# (7) Security Groups & Ingress for Redis and RDS
###############################################################################

# CloudFront security is implemented using origin custom headers instead of IP ranges
# This avoids hitting AWS security group rule limits (60 rules per security group)
# CloudFront has hundreds of IP ranges globally, which would exceed the limit
# Security group for ECS Service tasks
resource "aws_security_group" "ecs_service_sg" {
  name        = "${var.name}-service-sg"
  description = "Security group for ECS Fargate service"
  vpc_id      = var.vpc_id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"  # "-1" represents all protocols
    cidr_blocks      = ["0.0.0.0/0"]
    description      = "Allow all outbound traffic by default"
  }
}

resource "aws_security_group_rule" "alb_ingress_4000" {
  type                     = "ingress"
  from_port                = 4000
  to_port                  = 4000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_service_sg.id
  source_security_group_id = aws_security_group.alb_sg.id
  description              = "Allow Load Balancer to ECS"
}

resource "aws_security_group_rule" "alb_ingress_3000" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_service_sg.id
  source_security_group_id = aws_security_group.alb_sg.id
  description              = "Allow Load Balancer to ECS"
}


# Allow ECS tasks to connect to Redis
resource "aws_security_group_rule" "redis_ingress" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = var.redis_security_group_id
  source_security_group_id = aws_security_group.ecs_service_sg.id
  description              = "Allow ECS tasks to connect to Redis"
}

# Allow ECS tasks to connect to RDS
resource "aws_security_group_rule" "db_ingress" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.db_security_group_id
  source_security_group_id = aws_security_group.ecs_service_sg.id
  description              = "Allow ECS tasks to connect to RDS"
}

resource "aws_security_group" "alb_sg" {
  name        = "${var.name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = var.vpc_id

  # Ingress rules are managed via aws_security_group_rule below
  # to support dynamic allowed_cidrs

  tags = {
    Name = "${var.name}-alb-sg"
    SecurityModel = var.use_cloudfront ? "CloudFront-Protected" : (var.public_load_balancer ? "Public-WAF-Protected" : "Private-VPC-Only")
  }

  # Allow all outbound
  egress {
    description = "Allow all outbound"
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Determine which CIDRs to allow inbound on the ALB
locals {
  # If allowed_cidrs is explicitly set, use it (even for public ALBs).
  # If not set and private ALB, use private subnet CIDRs.
  # If not set and public ALB, default to empty (no auto-open 0.0.0.0/0).
  alb_ingress_cidrs = length(var.allowed_cidrs) > 0 ? var.allowed_cidrs : (
    var.public_load_balancer ? [] : var.private_subnets_cidr_blocks
  )
}

# HTTPS ingress — only created if there are CIDRs to allow
resource "aws_security_group_rule" "alb_https_ingress" {
  count             = length(local.alb_ingress_cidrs) > 0 ? 1 : 0
  type              = "ingress"
  description       = "HTTPS traffic"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = local.alb_ingress_cidrs
  security_group_id = aws_security_group.alb_sg.id
}

# HTTP ingress — only created if there are CIDRs to allow
resource "aws_security_group_rule" "alb_http_ingress" {
  count             = length(local.alb_ingress_cidrs) > 0 ? 1 : 0
  type              = "ingress"
  description       = "HTTP traffic"
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = local.alb_ingress_cidrs
  security_group_id = aws_security_group.alb_sg.id
}
