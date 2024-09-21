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

provider "digitalocean" {
  token = var.do_token

  spaces_access_id  = var.spaces_access_key
  spaces_secret_key = var.spaces_secret_key
}

# Kubernetes Cluster
resource "digitalocean_kubernetes_cluster" "skysome_cluster" {
  name    = "skysome-cluster"
  region  = var.region
  version = "1.31.1-do.0"

  node_pool {
    name       = "worker-pool"
    size       = "s-1vcpu-2gb"
    node_count = 1
  }
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

# Firewall
resource "digitalocean_firewall" "skysome_firewall" {
  name = "skysome-firewall"

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# Kubernetes configuration for web server deployment
resource "kubernetes_deployment" "skysome_web" {
  metadata {
    name = "skysome-web"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "skysome-web"
      }
    }

    template {
      metadata {
        labels = {
          app = "skysome-web"
        }
      }

      spec {
        container {
          image = "node:20"
          name  = "skysome-web"

          port {
            container_port = 3000
          }

          env {
            name  = "DATABASE_URL"
            value = digitalocean_database_cluster.skysome_db.uri
          }

          env {
            name  = "SPACES_ENDPOINT"
            value = digitalocean_spaces_bucket.skysome_storage.bucket_domain_name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "skysome_web" {
  metadata {
    name = "skysome-web"
  }

  spec {
    selector = {
      app = kubernetes_deployment.skysome_web.metadata[0].name
    }

    port {
      port        = 80
      target_port = 3000
    }

    type = "LoadBalancer"
  }
}

# Output important information
output "kubernetes_cluster_name" {
  value = digitalocean_kubernetes_cluster.skysome_cluster.name
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
