locals {
  cluster_name    = "clearavenue_cluster"
  vpc_name        = "clearavenue_cluster"
  eks_userarn     = "arn:aws:iam::921970209643:root"
  eks_username    = "root"
  common_tags = {
    terraform = var.terraform
  }
}


variable instance_type_nodes {
    default = "t2.small"
}

variable desired_nodes {
    type = number
    default = 3
}

#tags
variable "terraform" {
  default = "True"
}
