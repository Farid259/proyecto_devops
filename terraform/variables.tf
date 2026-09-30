variable "region" {
  type    = string
  default = "us-east-1"
}
variable "account_id" {
  description = "Cuenta AWS esperada; evita desplegar por error en otra cuenta."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Usar un ID de cuenta AWS de 12 digitos."
  }
}
variable "name" {
  type    = string
  default = "proyecto-devops-lab"
}
variable "admin_cidr" {
  description = "IPv4 publica del administrador con mascara /32."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && endswith(var.admin_cidr, "/32")
    error_message = "Indicar una IPv4 individual con /32."
  }
}
variable "admin_principal_arn" {
  description = "ARN IAM del rol o usuario administrador; no usar ARN STS de sesion."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:(role|user)/.+$", var.admin_principal_arn))
    error_message = "Se requiere un ARN IAM de rol o usuario."
  }
}
variable "kubernetes_version" {
  type    = string
  default = "1.35"
}
