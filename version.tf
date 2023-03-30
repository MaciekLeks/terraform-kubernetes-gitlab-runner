terraform {
  required_version = ">= 1.3.7"
  required_providers {
    helm = {
      version = ">= 2.9"
    }
    kubernetes = {
      version = ">= 2.19"
    }
  }
}
