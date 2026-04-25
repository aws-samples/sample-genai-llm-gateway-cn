output "LitellmEcsCluster" {
  value       = try(module.ecs_cluster[0].LitellmEcsCluster, "")
  description = "Name of the ECS Cluster"
}

output "LitellmEcsTask" {
  value       = try(module.ecs_cluster[0].LitellmEcsTask, "")
  description = "Name of the ECS Service"
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = try(module.eks_cluster[0].eks_cluster_name, "")
}

output "eks_deployment_name" {
  description = "Name of the Kubernetes deployment"
  value       = try(module.eks_cluster[0].eks_deployment_name, "")
}

output "cloudfront_distribution_id" {
  description = "The ID of the CloudFront distribution"
  value       = var.use_cloudfront ? try(module.ecs_cluster[0].cloudfront_distribution_id, "") : ""
}

output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution"
  value       = var.use_cloudfront ? try(module.ecs_cluster[0].cloudfront_domain_name, "") : ""
}

output "ServiceURL" {
  description = "The service URL"
  value = var.use_route53 ? "https://${var.record_name}.${var.hosted_zone_name}" : (
    var.use_cloudfront ? "https://${try(module.ecs_cluster[0].cloudfront_domain_name, "")}" : "https://${try(module.ecs_cluster[0].alb_dns_name, "")}"
  )
}

output "vpc_id" {
  description = "the vpc id we deployed to"
  value       = module.base.VpcId
}

output "ConfigBucketName" {
  description = "The Name of the configuration bucket"
  value       = module.base.ConfigBucketName
}

# Added to expose the CloudFront authentication secret once after creation
# This allows for troubleshooting and verification if needed
output "cloudfront_auth_secret" {
  description = "The CloudFront authentication secret (only shown once after creation)"
  value       = var.use_cloudfront ? try(module.ecs_cluster[0].cloudfront_auth_secret, null) : null
  sensitive   = true
}
