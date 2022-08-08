output "project" {
  value = var.project_id
}

output "regions" {
  value = var.region_cidrs
}

output "vpc" {
  value = google_compute_network.vpc.name
}

output "vpc_self_link" {
  value = google_compute_network.vpc.self_link
}

output "subnetwork_objects" {
  description = "The subnetwork object"
  value       = google_compute_subnetwork.vpc_subnetworks
}

output "subnet_names" {
  description = "The subnet names (in a regional map)"
  value       = {
    for region,subnet in google_compute_subnetwork.vpc_subnetworks: region => subnet.name
  }
}

output "ip_cidr_ranges" {
  description = "A list of the CIDR ranges in the network"
  value       = [for subnet in google_compute_subnetwork.vpc_subnetworks: subnet.ip_cidr_range]
}

output "vpc_connectors" {
  description = "A map (by region) of the VPC connector names"
  value       = {
    for region,connector in google_vpc_access_connector.connector: region => connector.name
  }
}

output "private_service_connection" {
  description = "The private service connection for the VPC"
  value       = google_service_networking_connection.private_service_connection
}
