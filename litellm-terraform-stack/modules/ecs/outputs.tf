###############################################################################
# (12) Outputs
###############################################################################
output "LitellmEcsCluster" {
  value       = aws_ecs_cluster.this.name
  description = "Name of the ECS Cluster"
}

output "LitellmEcsTask" {
  value       = aws_ecs_service.litellm_service.name
  description = "Name of the ECS Service"
}

output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "The DNS name of the ALB"
}

output "alb_zone_id" {
  value       = aws_lb.this.zone_id
  description = "The zone ID of the ALB"
}

output "cloudfront_distribution_id" {
  value       = var.use_cloudfront ? aws_cloudfront_distribution.this[0].id : ""
  description = "The ID of the CloudFront distribution"
}

output "cloudfront_domain_name" {
  value       = var.use_cloudfront ? aws_cloudfront_distribution.this[0].domain_name : ""
  description = "The domain name of the CloudFront distribution"
}

output "ServiceURL" {
  description = "The service URL"
  value = var.use_route53 ? "https://${var.record_name}.${var.hosted_zone_name}" : (
    var.use_cloudfront ? "https://${aws_cloudfront_distribution.this[0].domain_name}" : "https://${aws_lb.this.dns_name}"
  )
}

output "cloudfront_auth_secret" {
  description = "The CloudFront authentication secret (only shown once after creation)"
  value       = var.use_cloudfront ? random_password.cloudfront_secret[0].result : null
  sensitive   = true
}
