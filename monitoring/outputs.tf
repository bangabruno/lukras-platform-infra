output "sns_topic_arn" {
  description = "ARN of the SNS topic that receives ECS failure alerts"
  value       = aws_sns_topic.ecs_failure_topic.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function responsible for sending Telegram alerts"
  value       = aws_lambda_function.ecs_failure_notifier.function_name
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule that captures ECS task failures"
  value       = aws_cloudwatch_event_rule.ecs_task_failure_rule.name
}
