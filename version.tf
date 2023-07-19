terraform {
  required_version = ">= 1.3.3"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.10"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.22"
    }
  }
}
