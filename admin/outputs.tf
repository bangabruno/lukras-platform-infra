output "admin_service_name" {
  value       = aws_ecs_service.admin.name
  description = "ECS service name for admin"
}

output "admin_alb_dns" {
  value       = try(aws_lb.admin[0].dns_name, null)
  description = "Public ALB DNS (null se admin_enable_alb = false)"
}
