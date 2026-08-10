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
  description = "AWS Secrets Manager secret name — referenced by the ESO ExternalSecret"
}

output "db_secret_arn" {
  value       = aws_secretsmanager_secret.db_credentials.arn
  description = "ARN of the DB credentials secret"
}

output "eso_role_arn" {
  value       = aws_iam_role.eso.arn
  description = "IRSA role ARN annotated on the ESO service account"
}
