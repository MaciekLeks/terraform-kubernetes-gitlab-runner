variable "cluster_name" {
  description = "The name of the GKE cluster to create"
  type        = string
}

variable "project_id" {
  description = "the project ID on GCP"
  type        = string
}

variable "region" {
  description = "the region to deploy the cluster in"
  type        = string
}

variable "network" {
  description = "The name of the VPC to deploy the cluster in"
  type        = string
}

variable "subnet" {
  description = "The subnet name to deploy the cluster in within the VPC"
  type        = string
}

variable "cluster_secondary_range_name" {
  description = "The secondary subnet name to use when assigning IPs in the cluster"
  type        = string
}

variable "gke_machine_type" {
  description = "The machine types to use as node"
  type        = string
}

variable "runner_tags" {
  description = "The tags to register the runner with. This tags will be used on gitlab to be able to run jobs on the runner"
  type        = string
}

variable "runner_registration_token" {
  description = "The token (gotten from gitlab) to use during runner registration"
  type        = string
}

variable "runner_namespace" {
  description = "The namespace to deploy the runner in"
  type        = string
}

variable "runner_machine_type" {
  description = "The machine type to use when creating the node pools"
  type        = string
}

