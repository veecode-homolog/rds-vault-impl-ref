provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.aws_region
}

provider "kubernetes" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = module.cluster.cluster_certificate_authority_data
  token                  = module.cluster.kubeconfig_token
}
provider "vault" {
  address = local.config.vault_address
  token =  local.config.vault_token
  }