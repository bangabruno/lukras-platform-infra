output "admin_service_name" {
  value = aws_ecs_service.admin.name
}

output "admin_task_definition" {
  value = aws_ecs_task_definition.admin.family
}
