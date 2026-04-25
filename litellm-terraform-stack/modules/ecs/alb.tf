###############################################################################
# (8) Application Load Balancer, Listener, Target Groups
###############################################################################
# ALB
resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  subnets            = var.public_load_balancer ? var.public_subnets : var.private_subnets
  # You need to supply a security group for the ALB itself:
  security_groups    = [aws_security_group.alb_sg.id]
  internal           = var.public_load_balancer ? false : true
  idle_timeout       = 60
  drop_invalid_header_fields = true
  access_logs {
    bucket  = aws_s3_bucket.access_log_bucket.bucket
    prefix  = "alb-access-logs-"
    enabled = true
   }
}

# HTTP Listener for CloudFront origin connection
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  
  # Use tg_4000 as the default
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_4000.arn
  }
}

# HTTPS Listener
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  
  # Use ACM certificate if provided, otherwise use self-signed certificate
  certificate_arn   = var.certificate_arn != "" ? var.certificate_arn : aws_acm_certificate.self_signed[0].arn

  # Instead of a fixed-response 404, use tg_4000 as the default.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_4000.arn
  }
}

# Create a self-signed certificate if no certificate ARN is provided
resource "tls_private_key" "self_signed" {
  count     = var.certificate_arn == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "self_signed" {
  count           = var.certificate_arn == "" ? 1 : 0
  private_key_pem = tls_private_key.self_signed[0].private_key_pem

  subject {
    common_name  = "litellm-gateway.local"
    organization = "LiteLLM Gateway"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "self_signed" {
  count            = var.certificate_arn == "" ? 1 : 0
  private_key      = tls_private_key.self_signed[0].private_key_pem
  certificate_body = tls_self_signed_cert.self_signed[0].cert_pem

  lifecycle {
    create_before_destroy = true
  }
}

# Target Group for port 4000 (LiteLLMContainer)
resource "aws_lb_target_group" "tg_4000" {
  name        = "${var.name}-4000"
  port        = 4000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health/liveliness"
    port                = "4000"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
  }
}

# Target Group for port 3000 (MiddlewareContainer)
resource "aws_lb_target_group" "tg_3000" {
  name        = "${var.name}-3000"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/bedrock/health/liveliness"
    port                = "3000"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
  }
}

# Health check exception rule - highest priority
# Allows CloudFront to perform health checks without requiring the authentication header
resource "aws_lb_listener_rule" "health_check_exception" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = aws_lb_listener.https.arn
  priority     = 4  # Highest priority we can safely use

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_4000.arn
  }

  # Explicit health check paths - avoid wildcards for clarity
  condition {
    path_pattern {
      values = [
        "/",                         # Root path
        "/health",                   # Base health endpoint
        "/health/liveliness",        # Specific health endpoint
        "/bedrock/health/liveliness" # Middleware health endpoint
      ]
    }
  }
}

# CloudFront authentication rule - accepts traffic with the secret header
# This provides an additional security layer to prevent direct ALB access
resource "aws_lb_listener_rule" "cloudfront_auth" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = aws_lb_listener.https.arn
  priority     = 5  # Second priority, after health checks

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_4000.arn
  }

  # Check for the CloudFront secret header
  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = ["litellm-cf-${random_password.cloudfront_secret[0].result}"]
    }
  }
}

# Reject requests without CloudFront header when CloudFront is enabled
# This is the last line of defense for non-health-check paths
resource "aws_lb_listener_rule" "reject_direct_access" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = aws_lb_listener.https.arn
  priority     = 6  # Third priority

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\": \"Access denied. Direct access to this endpoint is not allowed.\"}"
      status_code  = "403"
    }
  }

  # Match all paths - since higher priority rules will handle exceptions
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

# Default catch-all rule for forwarding traffic when CloudFront is not enabled
resource "aws_lb_listener_rule" "catch_all" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 99

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_4000.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}


# Example: Listener Rules for path patterns & priorities
# bedrock model
resource "aws_lb_listener_rule" "bedrock_models" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 16

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/bedrock/model/*"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }
}

# OpenAICompletions
resource "aws_lb_listener_rule" "openai_completions" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 15

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/v1/chat/completions"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }
}

# ChatCompletions
resource "aws_lb_listener_rule" "chat_completions" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 14

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/chat/completions"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }
}

# ChatHistory
resource "aws_lb_listener_rule" "chat_history" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 8

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/chat-history"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }
}

# BedrockChatHistory
resource "aws_lb_listener_rule" "bedrock_chat_history" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 9

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/bedrock/chat-history"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }
}

# BedrockLiveliness
resource "aws_lb_listener_rule" "bedrock_liveliness" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/bedrock/health/liveliness"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }
}

# SessionIds
resource "aws_lb_listener_rule" "session_ids" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 11

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/session-ids"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }
}

# KeyGenerate
resource "aws_lb_listener_rule" "key_generate" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 12

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/key/generate"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }
}

# UserNew
resource "aws_lb_listener_rule" "user_new" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 13

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/user/new"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }
}

# HTTP Listener Rules for CloudFront to ALB communication
# ---------------------------------------------------------------------------

# Health check exception rule for HTTP - highest priority
resource "aws_lb_listener_rule" "health_check_exception_http" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 4  # Highest priority we can safely use

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_4000.arn
  }

  # Explicit health check paths - avoid wildcards for clarity
  condition {
    path_pattern {
      values = [
        "/",                         # Root path
        "/health",                   # Base health endpoint
        "/health/liveliness",        # Specific health endpoint
        "/bedrock/health/liveliness" # Middleware health endpoint
      ]
    }
  }
}

# Duplicate all path-specific rules for the HTTP listener with header authentication

# bedrock model for HTTP
resource "aws_lb_listener_rule" "bedrock_models_http" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 16

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/bedrock/model/*"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }

  # Add CloudFront Secret header validation
  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = ["litellm-cf-${random_password.cloudfront_secret[0].result}"]
    }
  }
}

# OpenAICompletions for HTTP
resource "aws_lb_listener_rule" "openai_completions_http" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 15

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/v1/chat/completions"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }

  # Add CloudFront Secret header validation
  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = ["litellm-cf-${random_password.cloudfront_secret[0].result}"]
    }
  }
}

# ChatCompletions for HTTP
resource "aws_lb_listener_rule" "chat_completions_http" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 14

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/chat/completions"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }

  # Add CloudFront Secret header validation
  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = ["litellm-cf-${random_password.cloudfront_secret[0].result}"]
    }
  }
}

# ChatHistory for HTTP
resource "aws_lb_listener_rule" "chat_history_http" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 8

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/chat-history"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }

  # Add CloudFront Secret header validation
  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = ["litellm-cf-${random_password.cloudfront_secret[0].result}"]
    }
  }
}

# BedrockChatHistory for HTTP
resource "aws_lb_listener_rule" "bedrock_chat_history_http" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 9

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/bedrock/chat-history"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }

  # Add CloudFront Secret header validation
  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = ["litellm-cf-${random_password.cloudfront_secret[0].result}"]
    }
  }
}

# BedrockLiveliness for HTTP
resource "aws_lb_listener_rule" "bedrock_liveliness_http" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/bedrock/health/liveliness"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }

  # Add CloudFront Secret header validation
  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = ["litellm-cf-${random_password.cloudfront_secret[0].result}"]
    }
  }
}

# SessionIds for HTTP
resource "aws_lb_listener_rule" "session_ids_http" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 11

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/session-ids"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }

  # Add CloudFront Secret header validation
  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = ["litellm-cf-${random_password.cloudfront_secret[0].result}"]
    }
  }
}

# KeyGenerate for HTTP
resource "aws_lb_listener_rule" "key_generate_http" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 12

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/key/generate"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }

  # Add CloudFront Secret header validation
  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = ["litellm-cf-${random_password.cloudfront_secret[0].result}"]
    }
  }
}

# UserNew for HTTP
resource "aws_lb_listener_rule" "user_new_http" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 13

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_3000.arn
  }

  condition {
    path_pattern {
      values = ["/user/new"]
    }
  }

  condition {
    http_request_method {
      values = ["POST", "GET", "PUT"]
    }
  }

  # Add CloudFront Secret header validation
  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = ["litellm-cf-${random_password.cloudfront_secret[0].result}"]
    }
  }
}

# DEFAULT CATCH-ALL with CloudFront header for HTTP
resource "aws_lb_listener_rule" "catch_all_http" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 98

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_4000.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
  
  # Add CloudFront Secret header validation
  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = ["litellm-cf-${random_password.cloudfront_secret[0].result}"]
    }
  }
}

# Reject requests without CloudFront header - LAST PRIORITY
resource "aws_lb_listener_rule" "reject_direct_access_http" {
  count        = var.use_cloudfront ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 99  # Make sure this is the last priority

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\": \"Access denied. Direct access to this endpoint is not allowed.\"}"
      status_code  = "403"
    }
  }

  # Match all paths - since higher priority rules will handle exceptions
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

###############################################################################
# (11) Application Auto Scaling (CPU & Memory)
###############################################################################
resource "aws_appautoscaling_target" "ecs_service_target" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.litellm_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu_policy" {
  name               = "${var.name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_utilization_percent
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "memory_policy" {
  name               = "${var.name}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.memory_target_utilization_percent
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}
