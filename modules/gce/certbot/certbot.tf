variable "gcp_region" {
  description = "GCP region, e.g. us-east1"
  default     = "us-east1"
}

variable "gcp_project" {
  description = "GCP project name"
  default     = "np-platforms-cd-thd"
}

variable "service_account_name" {
  description = "certbot"
  default     = "certbot"
}

variable "bucket_name" {
  description = "np-platforms-cd-thd-halyard-bucket"
  default     = "np-platforms-cd-thd-halyard-bucket"
}

resource "google_storage_bucket" "bucket-config" {
  name          = "${var.gcp_project}-${var.bucket_name}-bucket"
  storage_class = "MULTI_REGIONAL"
}

resource "google_storage_bucket_object" "service_account_key_storage" {
  name         = ".gcp/${var.service_account_name}.json"
  content      = "${base64decode(google_service_account_key.svc_key.private_key)}"
  bucket       = "${var.bucket_name}"
  content_type = "application/json"
}

variable terraform_account {
  type    = "string"
  default = "terraform-account"
}

data "vault_generic_secret" "terraform-account" {
  path = "secret/${var.terraform_account}"
}

resource "google_service_account" "service_account" {
  display_name = "${var.service_account_name}"
  account_id   = "${var.service_account_name}"
}

resource "google_service_account_key" "svc_key" {
  service_account_id = "${google_service_account.service_account.name}"
}

resource "google_project_iam_member" "dns-admin" {
  role   = "roles/dns.admin"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_project_iam_member" "storage_admin" {
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

//roles/storage.objectAdmin
resource "google_project_iam_member" "objectAdmin" {
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_project_iam_member" "rolesviewer" {
  role   = "roles/viewer"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_project_iam_member" "roleseditor" {
  role   = "roles/editor"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_project_iam_member" "rolesbrowser" {
  role   = "roles/browser"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

provider "google" {
  credentials = "${data.vault_generic_secret.terraform-account.data[var.gcp_project]}"
  project     = "${var.gcp_project}"
  region      = "${var.gcp_region}"
}

data "template_file" "start_script" {
  template = "${file("${path.module}/initCertBot.sh")}"

  vars {
    # Allows us to push the key without checking it in or putting it in the storage bucketcd
    REPLACE = "${jsonencode(replace(base64decode(google_service_account_key.svc_key.private_key),"\n"," "))}"
    USER    = "${var.service_account_name}"
    BUCKET  = "${var.bucket_name}"
    REGION  = "${var.gcp_region}"
    PROJECT = "${var.gcp_project}"
  }
}

resource "google_compute_instance" "certbot-thd-spinnaker" {
  count                     = 1                       // Adjust as desired
  name                      = "certbot-thd-spinnaker"
  machine_type              = "n1-standard-4"         // smallest (CPU &amp; RAM) available instance
  zone                      = "${var.gcp_region}-c"
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-1804-lts"
    }
  }

  tags = ["certbot"]

  // Local SSD disk
  scratch_disk {}

  network_interface {
    network = "default"

    access_config {
      // Ephemeral IP - leaving this block empty will generate a new external IP and assign it to the machine
    }
  }

  metadata_startup_script = "${data.template_file.start_script.rendered}"

  service_account {
    email  = "${google_service_account.service_account.email}"
    scopes = ["userinfo-email", "compute-rw", "storage-full", "service-control", "https://www.googleapis.com/auth/cloud-platform"]
  }
}