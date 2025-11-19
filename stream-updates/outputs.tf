output "settings_updates_queue_arn" {
  value = aws_sqs_queue.account_user_trading_settings_updates.arn
}

output "settings_updates_queue_url" {
  value = aws_sqs_queue.account_user_trading_settings_updates.id
}

output "dynamodb_stream_lambda_name" {
  value = aws_lambda_function.dynamodb_stream_processor.function_name
}
