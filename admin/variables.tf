variable "aws_region" { type = string }
variable "project_name" { type = string }
variable "container_image" { type = string }
variable "ecs_cluster_arn" { type = string }
variable "log_group_name" { type = string }
variable "public_subnet_ids" { type = list(string) }

variable "task_execution_role" {
  type        = string
  description = "ARN da execution role usada pela task ECS"
}

variable "task_role_arn" {
  type        = string
  description = "ARN da task role usada pela task ECS"
}