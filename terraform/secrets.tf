# ---------------------------------------------------------------------------
# AWS Secrets Manager — DB credentials for the event-registration app
#
# Credentials are stored here as the single source of truth.
# Jenkins no longer holds DB passwords; Ansible fetches them at deploy time.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "event-app/db-credentials"
  description             = "MySQL credentials for the event-registration app"
  recovery_window_in_days = 0   # instant delete — fine for a learning project

  tags = {
    Project     = "event-registration-app"
    Environment = "demo"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  # Store as JSON so consumers can parse individual fields
  secret_string = jsonencode({
    DB_URL            = "jdbc:mysql://mysql-service:3306/eventdb"
    DB_USER           = "eventuser"
    DB_PASS           = var.mysql_password
    MYSQL_ROOT_PASSWORD = var.mysql_root_password
    MYSQL_DATABASE    = "eventdb"
    MYSQL_USER        = "eventuser"
    MYSQL_PASSWORD    = var.mysql_password
  })
}

# ---------------------------------------------------------------------------
# IAM — allow EKS worker nodes to read this specific secret
#
# Attached to the same node role that already has AmazonEBSCSIDriverPolicy.
# For a real workload, scope this further with IRSA (per-service-account
# IAM roles) instead of granting it to every node.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "secrets_read" {
  statement {
    sid    = "AllowReadEventAppDbSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.db_credentials.arn]
  }
}

resource "aws_iam_policy" "secrets_read" {
  name        = "EventAppSecretsRead"
  description = "Allow reading the event-app DB credentials from AWS Secrets Manager"
  policy      = data.aws_iam_policy_document.secrets_read.json
}

# Attach to every managed node group role in the cluster
resource "aws_iam_role_policy_attachment" "secrets_read" {
  for_each = module.eks.eks_managed_node_groups

  role       = each.value.iam_role_name
  policy_arn = aws_iam_policy.secrets_read.arn
}
