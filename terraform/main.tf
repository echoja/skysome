# Skysome Digital Ocean Terraform Configuration

terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

variable "region" {
  default = "sgp1"
}

variable "do_token" {}
variable "spaces_access_key" {}
variable "spaces_secret_key" {}
variable "github_token" {}

provider "digitalocean" {
  token = var.do_token

  spaces_access_id  = var.spaces_access_key
  spaces_secret_key = var.spaces_secret_key
}

# Database
resource "digitalocean_database_cluster" "skysome_db" {
  name       = "skysome-db"
  engine     = "pg"
  version    = "16"
  size       = "db-s-1vcpu-1gb"
  region     = var.region
  node_count = 1
}

# Storage (Spaces)
resource "digitalocean_spaces_bucket" "skysome_storage" {
  name   = "skysome-storage"
  region = var.region
  acl    = "private"
}

# Domain
resource "digitalocean_domain" "skysome_domain" {
  name = "skysome.one"
}

# App Platform
resource "digitalocean_app" "skysome_app" {
  spec {
    name   = "skysome-app"
    region = var.region

    service {
      name               = "skysome-web"
      instance_size_slug = "basic-xxs"
      instance_count     = 1

      image {
        registry_type        = "DOCKER_HUB"
        registry             = "ghcr.io"
        repository           = "echoja/skysome"
        registry_credentials = "echoja:${var.github_token}"
        tag                  = "latest"
      }

      http_port = 3000

      env {
        key   = "DATABASE_URL"
        value = digitalocean_database_cluster.skysome_db.uri
      }

      env {
        key   = "SPACES_ENDPOINT"
        value = digitalocean_spaces_bucket.skysome_storage.bucket_domain_name
      }
    }

    domain {
      name = digitalocean_domain.skysome_domain.name
      type = "PRIMARY"
    }
  }
}



# Output important information
output "app_url" {
  value = digitalocean_app.skysome_app.live_url
}

output "database_uri" {
  value     = digitalocean_database_cluster.skysome_db.uri
  sensitive = true
}

output "spaces_bucket_name" {
  value = digitalocean_spaces_bucket.skysome_storage.name
}

output "domain_name" {
  value = digitalocean_domain.skysome_domain.name
}
