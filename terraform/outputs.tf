output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repo_url" {
  value = aws_ecr_repository.app.repository_url
}

output "db_secret_name" {
  value       = aws_secretsmanager_secret.db_credentials.name
  description = "AWS Secrets Manager secret name — pass this to Ansible as aws_secret_name"
}

output "db_secret_arn" {
  value       = aws_secretsmanager_secret.db_credentials.arn
  description = "ARN of the DB credentials secret"
}
