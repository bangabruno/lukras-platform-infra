data "aws_dynamodb_table" "account_user_trading_settings" {
  name = var.dynamodb_table_name
}
