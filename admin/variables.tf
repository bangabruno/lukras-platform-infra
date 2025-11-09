variable "aws_region" { type = string }
variable "project_name" { type = string }
variable "container_image" { type = string }

variable "ecs_cluster_arn" { type = string }
variable "log_group_name" { type = string }
variable "task_execution_role" { type = string }
variable "task_role_name" { type = string }
variable "public_subnet_ids" { type = list(string) }