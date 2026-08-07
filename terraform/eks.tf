module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.36"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  cluster_endpoint_public_access = true

  # Cluster addons — aws-ebs-csi-driver is required for any PVC to provision.
  # Without it, PVCs sit in Pending forever with no clear error (in-tree AWS
  # EBS provisioning was removed entirely in EKS 1.23+).
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

      # Simplest working setup for a learning project: grant the node's own
      # IAM role EBS CSI permissions directly, instead of a separate IRSA
      # role scoped to the driver's service account. Avoids an IRSA/OIDC
      # circular-dependency headache; trade-off is the node role has slightly
      # broader EBS permissions than strictly necessary — acceptable here,
      # worth tightening with IRSA if this ever becomes a real workload.
      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
  }

  enable_cluster_creator_admin_permissions = true
}
