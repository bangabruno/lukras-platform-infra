variable "aws_region"         { type = string }
variable "ecs_cluster_name"   { type = string }
variable "ecs_service_name"   { type = string }
variable "telegram_bot_token" {
  type = string
  sensitive = true
}
variable "telegram_chat_id"   { type = string }