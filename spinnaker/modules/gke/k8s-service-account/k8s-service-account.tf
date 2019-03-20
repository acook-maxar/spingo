resource "kubernetes_service_account" "service_account" {
  count = "${var.enable}"

  metadata {
    name      = "${var.service_account_name}"
    namespace = "${var.service_account_namespace}"
  }
}

resource "kubernetes_cluster_role_binding" "cluster_role_binding" {
  count = "${var.enable}"

  metadata {
    name = "${var.service_account_name}-cluster-role"
  }

  role_ref {
    kind      = "ClusterRole"
    name      = "cluster-admin"
    api_group = "rbac.authorization.k8s.io"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "${var.service_account_name}"
    namespace = "${var.service_account_namespace}"
    api_group = ""
  }

  depends_on = ["kubernetes_service_account.service_account"]
}

data "kubernetes_secret" "service_account_data" {
  count = "${var.enable}"

  metadata {
    name      = "${kubernetes_service_account.service_account.default_secret_name}"
    namespace = "${kubernetes_service_account.service_account.metadata.0.namespace}"
  }
}

data "template_file" "kubeconfig" {
  count    = "${var.enable}"
  template = "${file("${path.module}/kubeconfig.template")}"

  vars {
    CA_CERT = "${var.cluster_ca_certificates[var.cluster_list_index]}"
    HOST    = "https://${var.hosts[var.cluster_list_index]}"
    NAME    = "gke_${var.gcp_project}_${var.cluster_names[var.cluster_list_index]}_${var.cluster_region}"
    TOKEN   = "${lookup(data.kubernetes_secret.service_account_data.data, "token", "")}"
  }
}

resource "google_storage_bucket_object" "spinnaker_kubeconfig_file" {
  count        = "${var.enable}"
  name         = "${var.cluster_list_index == 0 ? ".kube/config" : ".kube/${var.cluster_names[var.cluster_list_index]}.config"}"
  content      = "${data.template_file.kubeconfig.rendered}"
  bucket       = "${var.bucket_name}"
  content_type = "application/text"
}