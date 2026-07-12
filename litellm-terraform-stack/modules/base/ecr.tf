# aws_region data source is declared in vpc-endpoints.tf

locals {
  # ECR pull-through cache from public.ecr.aws is not available in China regions
  ecr_ptc_enabled = (var.disable_outbound_network_access && var.deployment_platform == "EKS") && !startswith(data.aws_region.current.name, "cn-")
}

resource "aws_ecr_repository" "my_ecr_repository" {
  #checkov:skip=CKV_AWS_136:ECR encryption uses AES256 by default, KMS adds cost for cache repo
  count                = local.ecr_ptc_enabled ? 1 : 0
  name                 = "my-public-ecr-cache-repo"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  force_delete = true # replicates cdk.RemovalPolicy.DESTROY
}

resource "aws_ecr_pull_through_cache_rule" "alb_pull_through_cache" {
  count                 = local.ecr_ptc_enabled ? 1 : 0
  ecr_repository_prefix = aws_ecr_repository.my_ecr_repository[0].name
  upstream_registry_url = "public.ecr.aws"
}
