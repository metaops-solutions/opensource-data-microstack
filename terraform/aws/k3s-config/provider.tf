terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

provider "kubernetes" {
  config_path = "../cloud-resources/k3s.yaml"
  insecure    = true
}

provider "helm" {
  kubernetes = {
    config_path = "../cloud-resources/k3s.yaml"
    insecure    = true
  }
}

provider "aws" {
  region = var.aws_region
}

provider "kubectl" {
  config_path = "../cloud-resources/k3s.yaml"
}