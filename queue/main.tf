resource "aws_sqs_queue" "account_user_trading_settings_updates" {
  name                      = "account-user-trading-settings-updates"
  visibility_timeout_seconds = 30
  message_retention_seconds = 86400
}