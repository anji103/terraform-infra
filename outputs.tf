output "application_url" {
  description = "HTTPS endpoint
configure DNS for var.domain_name to point to the ALB."
  value       = "https://${var.domain_name}"
}
output "alb_dns_name" { value = aws_lb.this.dns_name }
output "alb_zone_id" { value = aws_lb.this.zone_id }
output "rds_endpoint" { value = aws_db_instance.mysql.address }
output "db_secret_arn" { value = aws_secretsmanager_secret.db.arn }
output "alb_logs_bucket" { value = aws_s3_bucket.alb_logs.bucket }
output "app_storage_bucket" { value = aws_s3_bucket.app_storage.bucket }
