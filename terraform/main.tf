module "network" {
  source = "./modules/network"
  name   = var.name
}
module "eks" {
  source              = "./modules/eks"
  name                = var.name
  subnet_ids          = module.network.subnet_ids
  admin_cidr          = var.admin_cidr
  admin_principal_arn = var.admin_principal_arn
  kubernetes_version  = var.kubernetes_version
}
