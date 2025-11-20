output "settings_updates_queue_url" {
  value = aws_sqs_queue.account_user_trading_settings_updates.id
}

output "settings_updates_queue_arn" {
  value = aws_sqs_queue.account_user_trading_settings_updates.arn
}