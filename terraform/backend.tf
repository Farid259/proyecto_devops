# Activar como backend.tf despues de crear el bucket y respaldar el estado local.
terraform {
  backend "s3" {}
}
