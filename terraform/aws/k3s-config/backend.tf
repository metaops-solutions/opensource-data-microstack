terraform {
  backend "s3" {
    bucket       = "microstack-terraform-aws-state"
    key          = "opensource-data-microstack-k3s-config/terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
  }
}
