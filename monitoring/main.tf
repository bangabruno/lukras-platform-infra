terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ======================================
# SNS Topic - used by CloudWatch alarms
# ======================================
resource "aws_sns_topic" "ecs_failure_topic" {
  name = "ecs-task-failure-topic"
}

# ======================================
# Lambda Function - Telegram notifier
# ======================================
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.mjs"
  output_path = "${path.module}/lambda/function.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "ecs-task-failure-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "ecs_failure_notifier" {
  function_name = "ecs-task-failure-notifier"
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn
  filename      = data.archive_file.lambda_zip.output_path

  environment {
    variables = {
      TELEGRAM_BOT_TOKEN = var.telegram_bot_token
      TELEGRAM_CHAT_ID   = var.telegram_chat_id
    }
  }
}

# ======================================
# SNS → Lambda subscription
# ======================================
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "sns-invoke-lambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecs_failure_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.ecs_failure_topic.arn
}

resource "aws_sns_topic_subscription" "lambda_sub" {
  topic_arn = aws_sns_topic.ecs_failure_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.ecs_failure_notifier.arn
}

# ======================================
# CloudWatch Alarm - running tasks below desired
# ======================================
resource "aws_cloudwatch_metric_alarm" "ecs_task_failure" {
  alarm_name          = "ecs-task-failure-alarm"
  alarm_description   = "Triggers when the number of RUNNING ECS tasks is lower than DESIRED count."
  namespace           = "AWS/ECS"
  metric_name         = "RunningTaskCount"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [aws_sns_topic.ecs_failure_topic.arn]

  treat_missing_data = "notBreaching"
}

# ======================================
# EventBridge Rule - ECS Task Failures
# ======================================
resource "aws_cloudwatch_event_rule" "ecs_task_failure_rule" {
  name        = "ecs-task-failure-rule"
  description = "Captures ECS Task STOPPED events that failed unexpectedly."

  event_pattern = jsonencode({
    "source": ["aws.ecs"],
    "detail-type": ["ECS Task State Change"],
    "detail": {
      "lastStatus": ["STOPPED"],
      "desiredStatus": ["RUNNING"]
    }
  })
}

resource "aws_cloudwatch_event_target" "ecs_task_failure_target" {
  rule      = aws_cloudwatch_event_rule.ecs_task_failure_rule.name
  target_id = "ecs-task-failure-lambda"
  arn       = aws_lambda_function.ecs_failure_notifier.arn
}

# Permission for EventBridge → Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "eventbridge-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecs_failure_notifier.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecs_task_failure_rule.arn
}
