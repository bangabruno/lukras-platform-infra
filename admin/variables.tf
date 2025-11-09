variable "aws_region"                { type = string }
variable "project_name"              { type = string }
variable "cluster_arn"               { type = string }
variable "public_subnet_ids"         { type = list(string) }
variable "log_group_name"            { type = string }
variable "efs_id"                    { type = string }
variable "task_execution_role_arn"   { type = string }
variable "task_role_arn"             { type = string }
variable "task_role_name"            { type = string }

# Admin service
# ==========================================
# Variable for Admin service container image
# ==========================================
variable "admin_container_image" {
  description = "ECR image for lukras-platform-admin service"
  type        = string
  default     = "659528245383.dkr.ecr.us-east-1.amazonaws.com/lukras-platform-admin:latest"
}
variable "admin_cpu" {
  type = number
  default = 256
}
variable "admin_memory" {
  type = number
  default = 512
}
variable "admin_container_port" {
  type = number
  default = 8080
}
variable "admin_desired_count" {
  type = number
  default = 2
}
variable "admin_enable_alb" {
  type = bool
  default = false
}
variable "admin_acm_certificate_arn" {
  type = string
  default = ""
  nullable = true
}
