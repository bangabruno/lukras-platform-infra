resource "aws_lambda_function" "dynamodb_stream_processor" {
  function_name = "${var.project_name}-dynamodb-stream-processor"
  role          = aws_iam_role.lambda_stream_role.arn
  handler       = "index.handler"
  runtime       = "python3.12"

  filename         = "${path.module}/lambda.zip"
  source_code_hash = filesha256("${path.module}/lambda.zip")

  timeout     = 10
  memory_size = 256

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.account_user_trading_settings_updates.id
    }
  }
}

resource "aws_lambda_event_source_mapping" "ddb_stream_trigger" {
  event_source_arn  = data.aws_dynamodb_table.account_user_trading_settings.stream_arn
  function_name     = aws_lambda_function.dynamodb_stream_processor.arn
  starting_position = "LATEST"
}
