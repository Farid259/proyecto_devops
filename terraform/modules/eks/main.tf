variable "name" { type = string }
variable "subnet_ids" { type = list(string) }
variable "admin_cidr" { type = string }
variable "admin_principal_arn" { type = string }
variable "kubernetes_version" { type = string }
resource "aws_iam_role" "cluster" {
  name = "${var.name}-cluster"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "eks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_eks_cluster" "lab" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }
  upgrade_policy { support_type = "STANDARD" }
  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = distinct(compact([var.admin_cidr, var.runner_cidr]))
  }
  depends_on = [aws_iam_role_policy_attachment.cluster]
}
resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.lab.name
  principal_arn = var.admin_principal_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.lab.name
  principal_arn = aws_eks_access_entry.admin.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}
resource "aws_iam_role" "node" {
  name = "${var.name}-node"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "node" {
  for_each   = toset(["AmazonEKSWorkerNodePolicy", "AmazonEC2ContainerRegistryPullOnly", "AmazonEKS_CNI_Policy"])
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
}
resource "aws_eks_node_group" "lab" {
  cluster_name    = aws_eks_cluster.lab.name
  node_group_name = "lab"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  version         = var.kubernetes_version
  ami_type        = "AL2023_x86_64_STANDARD"
  instance_types  = ["t3.medium"]
  capacity_type   = "ON_DEMAND"
  disk_size       = 20
  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }
  update_config { max_unavailable = 1 }
  depends_on = [aws_iam_role_policy_attachment.node]
}
output "cluster_name" { value = aws_eks_cluster.lab.name }

variable "cd_principal_arn" { type = string }
variable "runner_cidr" { type = string }
resource "aws_eks_access_entry" "cd" {
  count         = var.cd_principal_arn == "" ? 0 : 1
  cluster_name  = aws_eks_cluster.lab.name
  principal_arn = var.cd_principal_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "cd" {
  count         = var.cd_principal_arn == "" ? 0 : 1
  cluster_name  = aws_eks_cluster.lab.name
  principal_arn = aws_eks_access_entry.cd[0].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}
