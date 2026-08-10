module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.36"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  cluster_endpoint_public_access = true

  # Cluster addons
  cluster_addons = {
    coredns            = { most_recent = true }
    kube-proxy         = { most_recent = true }
    vpc-cni            = { most_recent = true }
    aws-ebs-csi-driver = { most_recent = true }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]
      capacity_type  = "SPOT"
      min_size       = 1
      max_size       = 2
      desired_size   = 1
      disk_size      = 20

      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
  }

  enable_cluster_creator_admin_permissions = true
}

# ---------------------------------------------------------------------------
# External Secrets Operator — installed via Helm into the cluster.
#
# ESO watches ExternalSecret resources and syncs secrets from AWS Secrets
# Manager into Kubernetes Secrets automatically. This replaces the old
# pattern of Ansible fetching SM values and applying K8s secrets manually.
#
# The ESO service account is annotated with the IRSA role ARN so that only
# the ESO pod can call secretsmanager:GetSecretValue — not every pod on
# every node (which was the old node-level IAM policy approach).
# ---------------------------------------------------------------------------

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.9.20"
  namespace        = "external-secrets"
  create_namespace = true
  wait             = true
  timeout          = 300

  # Annotate the ESO service account with the IRSA role so AWS SDK inside
  # the ESO pod picks up scoped credentials via the pod identity webhook.
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.eso.arn
  }

  depends_on = [module.eks]
}
