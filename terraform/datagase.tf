resource "digitalocean_database_cluster" "skysome-db-cluster" {
  name       = "skysome-db"
  engine     = "pg"
  version    = "16"
  size       = "db-s-1vcpu-1gb"
  region     = "sgp1"
  node_count = 1
}

/**
 * The skysome database within the cluster.
 */
resource "digitalocean_database_db" "skysome-db" {
  cluster_id = digitalocean_database_cluster.skysome-db-cluster.id
  name       = "skysome_DB"
}

/**
 * Database firewall rules.
 * These rules are two-way; we don't need both inbound and outbound.
 */
resource "digitalocean_database_firewall" "skysome-db-firewall" {
  depends_on = [digitalocean_droplet.skysome-server]

  # skysome's Digital Ocean droplet
  cluster_id = digitalocean_database_cluster.skysome-db-cluster.id
  rule {
    type  = "droplet"
    value = digitalocean_droplet.skysome-server.id
  }
  # The Redash server that we use for manual queries
  rule {
    type  = "ip_addr"
    value = var.redash_ip_address
  }
}

/**
 * A private database connection URI.
 * Github Actions uses this to set up a database connection from
 * the skysome code.  It's only usable from within Digital Ocean.
 */
output "database-connection-uri" {
  value      = digitalocean_database_cluster.skysome-db-cluster.private_uri
  sensitive  = true
}