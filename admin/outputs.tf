output "admin_service_name" {
  value       = aws_ecs_service.admin.name
  description = "ECS service name for admin"
}
