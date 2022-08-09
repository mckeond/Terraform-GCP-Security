# ----------------------------------------------------------------------------
# VPC network and subnetwork(s)
# ----------------------------------------------------------------------------
locals {
  # Need to tailor the PROJECT NAME for each new project
  network_base_name = "{PROJECT-NAME}-${var.env_name}"


# --------------------------------------------------------------------------
# Create a custom VPC with a limited set of subnets
# --------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  name                    = "${local.network_base_name}-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "vpc_subnetworks" {
  for_each                 = var.region_cidrs
  name                     = "${local.network_base_name}-subnet"
  project                  = var.project_id
  region                   = each.key
  network                  = google_compute_network.vpc.self_link
  ip_cidr_range            = each.value.cidr_range
  private_ip_google_access = true

  # Use the default VPC flow log config for now
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }

  dynamic "secondary_ip_range" {
    for_each = [for s in each.value.secondary_cidr_blocks : {
      name       = s.name
      cidr_range = s.cidr_range
    }]

    content {
      range_name    = "${google_compute_network.vpc.name}-${secondary_ip_range.value.name}"
      ip_cidr_range = secondary_ip_range.value.cidr_range
    }
  }
}


# --------------------------------------------------------------------------
# Create private DNS zones to redirect requests to Google APIs
#
# These zones redirect traffic to protected.googleapis.com because
# the services are supported by VPC service controls
# --------------------------------------------------------------------------
module "googleapi_redirect" {
  for_each = local.private_dns_zones
  source   = "../google_dns"

  env_name      = var.env_name
  project_id    = var.project_id
  base_labels   = {}
  vpc_id        = google_compute_network.vpc.id
  dns_zone_name = each.key
  dns_name      = each.value.dns_name
  vip_config    = each.value.vip_config
}

# ----------------------------------------------------------------------------
# Firewall - Allow communication within the subnet
# ----------------------------------------------------------------------------
resource "google_compute_firewall" "google_subnet_egress" {
  name        = "${google_compute_network.vpc.name}-internal-egress"
  network     = google_compute_network.vpc.self_link
  description = "Grant access to the Google VIPs addresses"
  allow {
    protocol = "all"
  }
  direction          = "EGRESS"
  priority           = "1000"
  destination_ranges = [for subnet in google_compute_subnetwork.vpc_subnetworks : subnet.ip_cidr_range]
}
resource "google_compute_firewall" "google_subnet_ingress" {
  name        = "${google_compute_network.vpc.name}-internal-ingress"
  network     = google_compute_network.vpc.self_link
  description = "Grant access to the Google VIPs addresses"
  allow {
    protocol = "all"
  }
  direction     = "INGRESS"
  priority      = "1000"
  source_ranges = [for subnet in google_compute_subnetwork.vpc_subnetworks : subnet.ip_cidr_range]
}


# ----------------------------------------------------------------------------
# Firewall - Allow communication to the Google API VIPs
# ----------------------------------------------------------------------------
resource "google_compute_firewall" "google_vip_access" {
  name        = "${google_compute_network.vpc.name}-vip-access"
  network     = google_compute_network.vpc.self_link
  description = "Grant access to the Google VIPs addresses"
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
  direction          = "EGRESS"
  priority           = "1000"
  destination_ranges = ["199.36.153.4/30", "199.36.153.8/30"]
}

# ----------------------------------------------------------------------------
# Firewall - Allow communication between dataflow nodes
# ----------------------------------------------------------------------------
resource "google_compute_firewall" "google_dataflow_node_out_access" {
  name        = "${google_compute_network.vpc.name}-dataflow-out-access"
  network     = google_compute_network.vpc.self_link
  description = "Grant access between dataflow nodes"
  allow {
    protocol = "all"
  }
  direction   = "INGRESS"
  priority    = "1000"
  source_tags = ["dataflow"]
}
resource "google_compute_firewall" "google_dataflow_node_in_access" {
  name        = "${google_compute_network.vpc.name}-dataflow-in-access"
  network     = google_compute_network.vpc.self_link
  description = "Grant access between dataflow nodes"
  allow {
    protocol = "all"
  }
  direction   = "EGRESS"
  priority    = "1000"
  target_tags = ["dataflow"]
}

# ----------------------------------------------------------------------------
# Firewall - Block all communication
#
# tfsec doesn't realize this is a "deny" rule
# ----------------------------------------------------------------------------
resource "google_compute_firewall" "block_external_access" {
  name        = "${google_compute_network.vpc.name}-block-external-access"
  network     = google_compute_network.vpc.self_link
  description = "Deny access to external IP addresses"
  deny {
    protocol = "all"
  }
  direction          = "EGRESS"
  priority           = "65000"
  destination_ranges = ["0.0.0.0/0"] #tfsec:ignore:google-compute-no-public-egress
}
