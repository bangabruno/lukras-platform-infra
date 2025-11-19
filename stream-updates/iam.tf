data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_stream_role" {
  name               = "${var.project_name}-stream-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_stream_policy" {
  statement {
    sid    = "DynamoDBStreamAccess"
    effect = "Allow"
    actions = [
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:ListStreams"
    ]
    resources = [
      data.aws_dynamodb_table.account_user_trading_settings.stream_arn
    ]
  }

  statement {
    sid    = "SendToSQS"
    effect = "Allow"
    actions = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.account_user_trading_settings_updates.arn]
  }

  statement {
    sid    = "LambdaLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_policy" "lambda_stream_policy" {
  name   = "${var.project_name}-lambda-stream-policy"
  policy = data.aws_iam_policy_document.lambda_stream_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_stream_role.name
  policy_arn = aws_iam_policy.lambda_stream_policy.arn
}
