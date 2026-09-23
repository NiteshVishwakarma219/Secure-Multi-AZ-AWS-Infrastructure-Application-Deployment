output "cloudfront_domain_name" {
  value = var.enable_cloudfront ? aws_cloudfront_distribution.main[0].domain_name : null
}

output "waf_web_acl_arn" {
  value = var.enable_cloudfront ? aws_wafv2_web_acl.main[0].arn : null
}

output "route53_zone_id" {
  value = local.zone_id
}

output "alb_certificate_arn" {
  value = aws_acm_certificate_validation.alb.certificate_arn
}