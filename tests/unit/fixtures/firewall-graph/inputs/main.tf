resource "terraform_data" "upstream" {
  input = var.configuration.revision
}
