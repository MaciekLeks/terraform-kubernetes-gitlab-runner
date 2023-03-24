terraform {
  required_version = ">= 1.3.7"
  required_providers {
    helm = {
    }
    kubernetes = {
    }
    google = {
      version = "~> 4.5"
    }
  }
}
