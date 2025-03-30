# Skysome Digital Ocean Terraform Configuration

terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
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


provider "digitalocean" {
  token             = var.do_token
  spaces_access_id  = var.spaces_access_key
  spaces_secret_key = var.spaces_secret_key
}

data "digitalocean_kubernetes_cluster" "skysome_cluster" {
  name       = digitalocean_kubernetes_cluster.skysome_cluster.name
  depends_on = [digitalocean_kubernetes_cluster.skysome_cluster]
}

provider "kubernetes" {
  host  = data.digitalocean_kubernetes_cluster.skysome_cluster.endpoint
  token = data.digitalocean_kubernetes_cluster.skysome_cluster.kube_config[0].token
  cluster_ca_certificate = base64decode(
    data.digitalocean_kubernetes_cluster.skysome_cluster.kube_config[0].cluster_ca_certificate
  )
}

provider "helm" {
  kubernetes {
    host  = data.digitalocean_kubernetes_cluster.skysome_cluster.endpoint
    token = data.digitalocean_kubernetes_cluster.skysome_cluster.kube_config[0].token
    cluster_ca_certificate = base64decode(
      data.digitalocean_kubernetes_cluster.skysome_cluster.kube_config[0].cluster_ca_certificate
    )
  }
}

resource "digitalocean_database_cluster" "skysome_db" {
  name       = "skysome-db"
  engine     = "pg"
  version    = "16"
  size       = "db-s-1vcpu-1gb"
  region     = var.region
  node_count = 1
}

resource "digitalocean_spaces_bucket" "skysome_storage" {
  name   = "skysome-storage"
  region = var.region
  acl    = "private"
}

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

resource "kubernetes_namespace" "skysome" {
  metadata {
    name = "skysome"
  }
  depends_on = [data.digitalocean_kubernetes_cluster.skysome_cluster]
}

# GitHub Container Registry 인증을 위한 Kubernetes Secret 생성
resource "kubernetes_secret" "ghcr_auth" {
  metadata {
    name      = "ghcr-auth"
    namespace = kubernetes_namespace.skysome.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.github_username
          password = var.github_token
          email = var.github_email
          auth = base64encode("${var.github_username}:${var.github_token}")
        }
      }
    })
  }

  depends_on = [data.digitalocean_kubernetes_cluster.skysome_cluster]
}

resource "kubernetes_deployment" "skysome_web" {
  metadata {
    name      = "skysome-web"
    namespace = kubernetes_namespace.skysome.metadata[0].name
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
          image = "ghcr.io/echoja/skysome:${var.web_image_tag}"
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

        image_pull_secrets {
          name = kubernetes_secret.ghcr_auth.metadata[0].name
        }
      }
    }
  }
  depends_on = [data.digitalocean_kubernetes_cluster.skysome_cluster]
}

resource "helm_release" "nginx_ingress" {
  name             = "nginx-ingress"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }
  depends_on = [data.digitalocean_kubernetes_cluster.skysome_cluster]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.17.1"

  set {
    name  = "installCRDs"
    value = "true"
  }
  depends_on = [data.digitalocean_kubernetes_cluster.skysome_cluster]
}

resource "digitalocean_domain" "skysome_domain" {
  name = var.domain_name
}

data "kubernetes_service" "nginx_ingress" {
  metadata {
    name      = "nginx-ingress-ingress-nginx-controller"
    namespace = "ingress-nginx"
  }

  depends_on = [helm_release.nginx_ingress]
}


resource "digitalocean_record" "www" {
  domain = digitalocean_domain.skysome_domain.name
  type   = "A"
  name   = "@"
  value  = data.kubernetes_service.nginx_ingress.status.0.load_balancer.0.ingress.0.ip

  depends_on = [helm_release.nginx_ingress]
}

resource "kubernetes_ingress_v1" "skysome_ingress" {
  metadata {
    name      = "skysome-ingress"
    namespace = kubernetes_namespace.skysome.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"              = "nginx"
      "cert-manager.io/cluster-issuer"           = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
    }
  }

  spec {
    tls {
      hosts       = [var.domain_name]
      secret_name = "skysome-tls"
    }

    rule {
      host = var.domain_name
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.skysome_web.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  # depends_on = [helm_release.nginx_ingress, kubernetes_manifest.cluster_issuer]
  depends_on = [helm_release.nginx_ingress]
}

resource "kubernetes_service" "skysome_web" {
  metadata {
    name      = "skysome-web"
    namespace = kubernetes_namespace.skysome.metadata[0].name
  }

  spec {
    selector = {
      app = kubernetes_deployment.skysome_web.metadata[0].name
    }

    port {
      port        = 80
      target_port = 3000
    }

    type = "ClusterIP"
  }
}

// 이 요소는 kubernetes cluster 가 먼저 켜져 있어야 제대로 동작합니다. 
resource "kubernetes_manifest" "cluster_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        email  = var.email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-prod-account-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [helm_release.cert_manager, data.digitalocean_kubernetes_cluster.skysome_cluster]
}

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

output "load_balancer_ip" {
  value = data.digitalocean_kubernetes_cluster.skysome_cluster.ipv4_address
}
