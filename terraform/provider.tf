
terraform {
  # A list of required providers.
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }

  cloud {
    organization = "thkimzizi"
    workspaces {
      name = "skysome"
    }
  }
}

# Provider config for Digital Ocean.
provider "digitalocean" {
  token = var.do_token
}
