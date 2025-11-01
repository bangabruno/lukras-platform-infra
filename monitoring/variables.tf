###########################################################
# Monitoring Module Variables
# Used to configure ECS failure monitoring and Telegram alerts
###########################################################

variable "aws_region" {
  description = "AWS region where all monitoring resources will be created."
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name to monitor. If empty, alarm dimensions will be ignored (EventBridge will still capture all ECS failures)."
  type        = string
  default     = ""
}

variable "telegram_bot_token" {
  description = "Telegram bot token used by the Lambda function to send alerts."
  type        = string
  sensitive   = true
}

variable "telegram_chat_id" {
  description = "Telegram chat ID (user or group) where failure notifications will be sent."
  type        = string
}

variable "enable_cluster_alarm" {
  description = "Whether to create a CloudWatch alarm that monitors ECS cluster task count (default: true)."
  type        = bool
  default     = true
}
