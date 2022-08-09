terraform {
  required_version = ">= 0.13.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "<5.0,>= 3.83"
    }
  }

  provider_meta "google" {
    module_name = "blueprints/terraform/terraform-google-network:routes/v5.2.0"
  }
}
