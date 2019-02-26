############################################
resource "google_container_cluster" "cluster" {
  name               = "${var.cluster_name}-${var.cluster_region}"
  region             = "${var.cluster_region}"
  min_master_version = "${var.gke_version}"
  node_version       = "${var.gke_version}"
  logging_service    = "${var.logging_service}"
  monitoring_service = "${var.monitoring_service}"
  provider           = "google-beta"

  # Required for now, see:
  # https://github.com/mcuadros/terraform-provider-helm/issues/56
  # https://github.com/terraform-providers/terraform-provider-kubernetes/pull/73
  enable_legacy_abac = "${var.enable_legacy_abac}"

  # Remove the default node pool during cluster creation.
  # We use google_container_node_pools for better control and
  # less disruptive changes.
  # https://github.com/terraform-providers/terraform-provider-google/issues/1712#issuecomment-410317055
  remove_default_node_pool = true

  node_pool {
    name = "default-pool"
  }

  lifecycle {
    ignore_changes = ["node_pool"]
    ignore_changes = ["network"]
  }
}

# Primary node pool
resource "google_container_node_pool" "primary_pool" {
  name               = "${var.cluster_name}-${var.cluster_region}-primary-pool"
  cluster            = "${google_container_cluster.cluster.name}"
  region             = "${var.cluster_region}"
  version            = "${var.gke_version}"
  initial_node_count = 1
  provider           = "google-beta"

  autoscaling {
    min_node_count = "${var.min_node_count}"
    max_node_count = "${var.max_node_count}"
  }

  node_config {
    machine_type = "${var.machine_type}"
    oauth_scopes = ["${var.oauth_scopes}"]
  }
}

resource "google_compute_address" "ui" {
  name = "spinnaker-ui"
}

resource "google_compute_address" "api" {
  name = "spinnaker-api"
}

resource "vault_generic_secret" "vault-api" {
  path = "secret/vault-api"

  data_json = <<-EOF
              {"address":"${google_compute_address.api.address}"}
              EOF
}

resource "vault_generic_secret" "vault-ui" {
  path = "secret/vault-ui"

  data_json = <<-EOF
              {"address":"${google_compute_address.ui.address}"}
              EOF
}

resource "google_dns_managed_zone" "project_zone" {
  name     = "${var.gcp_project}"
  dns_name = "${var.gcp_project}.gcp.homedepot.com."
}

/*
Note: The Google Cloud DNS API requires NS records be present at all times. 
To accommodate this, when creating NS records, the default records Google 
automatically creates will be silently overwritten. Also, when destroying NS 
records, Terraform will not actually remove NS records, but will report that 
it did.
reference: https://www.terraform.io/docs/providers/google/r/dns_record_set.html
*/
resource "google_dns_record_set" "spinnaker-ui" {
  name = "spinnaker.${google_dns_managed_zone.project_zone.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = "${google_dns_managed_zone.project_zone.name}"

  rrdatas = ["${google_compute_address.ui.address}"]
}

resource "google_dns_record_set" "spinnaker-api" {
  name = "spinnaker-api.${google_dns_managed_zone.project_zone.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = "${google_dns_managed_zone.project_zone.name}"

  rrdatas = ["${google_compute_address.api.address}"]
}

output "host" {
  value     = "${google_container_cluster.cluster.endpoint}"
  sensitive = false
}

output "client_certificate" {
  value = "${google_container_cluster.cluster.master_auth.0.client_certificate}"
}

output "client_key" {
  value = "${google_container_cluster.cluster.master_auth.0.client_key}"
}

output "cluster_ca_certificate" {
  value = "${google_container_cluster.cluster.master_auth.0.cluster_ca_certificate}"
}