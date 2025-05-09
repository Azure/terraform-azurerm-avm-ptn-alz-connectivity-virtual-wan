output "linting" {
  value = {
    connectivity_type = var.connectivity_type
  }
}

output "test_outputs" {
  value = module.test
}
