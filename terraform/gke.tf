# Private GKE cluster — nodes have no public IPs; egress via Cloud NAT.
# The control plane endpoint stays public but is restricted to var.admin_cidr so kubectl works.

resource "google_container_cluster" "gke" {
  name     = "${var.prefix}-gke"
  location = var.zone

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false # lab environment — keep teardown clean

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.private.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Who may reach the Kubernetes API. A genuine control, not one of the
  # intentional weaknesses — worth saying out loud, since SSH to the Mongo VM is
  # deliberately open to the world and the contrast is the point.
  #
  # Adding an entry needs no HCL edit:
  #   extra_admin_cidrs = [{ cidr = "203.0.113.7/32", name = "vpn-egress" }]
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = concat(
        [{ cidr = var.admin_cidr, name = "admin" }],
        var.extra_admin_cidrs,
      )
      content {
        cidr_block   = cidr_blocks.value.cidr
        display_name = cidr_blocks.value.name
      }
    }
  }

  # 🛡️ NATIVE DETECTIVE — GKE Security Posture.
  # GCP-native, project-scoped detection of workload misconfiguration and image
  # vulnerabilities. This is the answer to "native CSP tooling to detect the
  # misconfigurations" in a sandbox where Security Command Center is denied at
  # the organisation: BASIC audits workload config (privileged, runAsRoot,
  # missing limits, over-broad RBAC); VULNERABILITY_BASIC adds CVE scanning of
  # the images actually running. Findings surface in the GKE Security Posture
  # dashboard and Cloud Logging — no agent, nothing installed.
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  # 🛡️ NATIVE PREVENTATIVE — Binary Authorization.
  # Admission control enforced by the GKE CONTROL PLANE itself, not a pod we
  # installed. Only images allowed by the project policy (security-binauthz.tf)
  # may run. This is the CSP-native counterpart to the Gatekeeper constraint —
  # same "reject a new bad action, live" demo, one layer down and vendor-native,
  # which removes any doubt about whether the preventative control is a *cloud*
  # control or a Kubernetes one.
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }
}

resource "google_container_node_pool" "primary" {
  name       = "${var.prefix}-np"
  cluster    = google_container_cluster.gke.name
  location   = var.zone
  node_count = 2

  # Sized for the CloudLabs $200 sandbox cap, not for production.
  # NodeGoat is a small Node app; 2 x e2-medium (2 vCPU / 4 GB each) comfortably
  # runs it alongside the GKE system pods and roughly halves compute spend
  # versus e2-standard-2. pd-standard over the default balanced disk for the
  # same reason. Scale up in a real deployment.
  node_config {
    machine_type = "e2-medium"
    disk_size_gb = 30
    disk_type    = "pd-standard"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}
