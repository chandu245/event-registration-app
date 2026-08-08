variable "aws_region" {
  default = "ap-southeast-1"
}

variable "cluster_name" {
  default = "event-app-cluster"
}

variable "node_instance_type" {
  default = "t3.medium"
}

# DB credentials — passed at apply time via -var or TF_VAR_* env vars.
# These seed the initial AWS Secrets Manager secret; never hardcode values here.
variable "mysql_password" {
  description = "MySQL application-user password"
  type        = string
  sensitive   = true
}

variable "mysql_root_password" {
  description = "MySQL root password"
  type        = string
  sensitive   = true
}
