output "cloudtrail_arn" {
  value = aws_cloudtrail.main.arn
}

output "flow_log_group_name" {
  value = aws_cloudwatch_log_group.flow_logs.name
}

output "guardduty_detector_id" {
  value = try(aws_guardduty_detector.main[0].id, null)
}

output "security_response_lambda_arn" {
  value = aws_lambda_function.security_response.arn
}
