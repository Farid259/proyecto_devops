# Plantilla para generar la politica de provisionamiento; no crea recursos IAM.
locals {
  lab_provision_policy = templatefile("${path.module}/iam/lab-provision-policy.json.tftpl", {
    account_id = var.account_id
  })
}
