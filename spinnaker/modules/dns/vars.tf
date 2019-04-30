variable "gcp_project" {
  description = "GCP project name"
}

variable "cluster_config" {
  type = "map"
}

variable "dns_name" {
  description = "description"
}

variable "ui_ip_addresses" {
  type = "list"
}

variable "api_ip_addresses" {
  type = "list"
}
