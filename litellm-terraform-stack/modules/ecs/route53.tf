# Only lookup the Route53 zone if use_route53 is true
data "aws_route53_zone" "this" {
  count        = var.use_route53 ? 1 : 0
  name         = var.hosted_zone_name
  private_zone = !var.public_load_balancer
}

# Only create Route53 records if use_route53 is true
resource "aws_route53_record" "alb_alias" {
  count   = var.use_route53 ? 1 : 0
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = var.record_name
  type    = "A"

  alias {
    # If CloudFront is enabled, point to CloudFront, otherwise point to ALB
    name                   = var.use_cloudfront ? aws_cloudfront_distribution.this[0].domain_name : aws_lb.this.dns_name
    zone_id                = var.use_cloudfront ? aws_cloudfront_distribution.this[0].hosted_zone_id : aws_lb.this.zone_id
    evaluate_target_health = true
  }

  depends_on = [aws_cloudfront_distribution.this]
}
