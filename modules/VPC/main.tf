# ----------------------------------------------------------------------------
# VPC network and subnetwork(s)
# ----------------------------------------------------------------------------
locals {
  network_base_name = "{PROJECT-NAME}-${var.env_name}"

  # Internal DNS zones to redirect Google API requests to keep
  # communication within the VPC
  private_dns_zones = {
    # This zone will redirect API requests to *.googleapis.com to
    # either the restricted Virtual IP range or the private virtual
    # IP range, depending on if the service supports VPC integration
    googleapi-redirect = {
      dns_name = "googleapis.com."

      vip_config = {
        # Services with VPC support must be directed to the restricted VIPs
        "restricted.googleapis.com." = {
          vip_type = "restricted"
          cname_records = [
            "*.googleapis.com."
          ]
        }

        # Services without VPC support must be directed to the private
        # VIP range instead of the restricted one
        "private.googleapis.com." = {
          vip_type = "private"
          cname_records = [
            "identitytoolkit.googleapis.com."
          ]
        }
      }
    }

    # Create a DNS zone to redirect all calls to *.run.app
    # to the GCP restricted.googleapis.com VIP
    # This is done only with an A-record
    run-redirect = {
      dns_name = "run.app."
      vip_config = {
        "*.run.app." = {
          vip_type      = "restricted"
          cname_records = []
        }
      }
    }

    # Create a DNS zone to redirect all calls to container registry
    # to the GCP restricted.googleapis.com VIP
    gcr-redirect = {
      dns_name = "gcr.io."
      vip_config = {
        "gcr.io." = {
          vip_type      = "restricted"
          cname_records = ["*.gcr.io."]
        }
      }
    }

    # Create a DNS zone to redirect all calls to artifact registry
    # to the GCP restricted.googleapis.com VIP
    artifactory-redirect = {
      dns_name = "pkg.dev."
      vip_config = {
        "pkg.dev." = {
          vip_type      = "restricted"
          cname_records = ["*.pkg.dev."]
        }
      }
    }
  }

  common_labels = {}
  dns_ttl       = 300
}

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

# -------------------------------------------------------------
# Allow Private IP access
# -------------------------------------------------------------
resource "google_compute_global_address" "service_range" {
  name          = "${local.network_base_name}-peer-range-${var.env_name}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.self_link
}

resource "google_service_networking_connection" "private_service_connection" {
  network                 = google_compute_network.vpc.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.service_range.name]
}

# VPC connector names have length limits
resource "google_vpc_access_connector" "connector" {
  for_each      = var.region_cidrs
  name          = "{PROJECT-NAME}-${each.key}"
  region        = each.key
  ip_cidr_range = each.value.connector_range
  network       = google_compute_network.vpc.name

  lifecycle {
    create_before_destroy = true
  }
}

# ----------------------------------------------------------------------------
# Firewall - Allow SSH to the bastion host
# ----------------------------------------------------------------------------
#TODO - identify a safe source set of IP ranges
#resource "google_compute_firewall" "allow_ssh_for_sql" {
#  name          = "${google_compute_network.vpc.name}-allow-sql-access"
#  network       = google_compute_network.vpc.self_link
#  description   = "Allow SSH traffic to SQL bastion hosts"
#  allow {
#    protocol = "icmp"
#  }
#  allow {
#    protocol = "tcp"
#    ports    = ["22"]
#  }
#  priority      = "1000"
#  source_ranges = ["0.0.0.0/0"]
#  target_tags   = ["sql-access"]
#}

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
