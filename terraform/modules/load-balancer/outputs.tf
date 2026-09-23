output "alb_arn" {
  value = aws_lb.main.arn
}

# CloudWatch metric dimensions for ALB/TargetGroup want the short
# "arn_suffix" form (e.g. "app/name/id"), not the full ARN.
output "alb_arn_suffix" {
  value = aws_lb.main.arn_suffix
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "alb_zone_id" {
  value = aws_lb.main.zone_id
}

output "frontend_tg_arn" {
  value = aws_lb_target_group.frontend.arn
}

output "backend_tg_arn" {
  value = aws_lb_target_group.backend.arn
}

output "target_group_arns" {
  value = [aws_lb_target_group.frontend.arn, aws_lb_target_group.backend.arn]
}

output "target_group_arn_suffixes" {
  value = [aws_lb_target_group.frontend.arn_suffix, aws_lb_target_group.backend.arn_suffix]
}
