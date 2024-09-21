# Terraform resources for the skysome_Bot droplet.

/**
 * skysome's SSH key.  Saved in Github Actions secrets.
 * You need to allow your IP through the firewall and
 * have this SSH key to get into the droplet.
 */
data "digitalocean_ssh_key" "skysome-key" {
  name = "skysome-key"
}

/**
 * skysome's droplet.
 * Currently the smallest droplet that Digital Ocean offers,
 */
resource "digitalocean_droplet" "skysome-server" {
  image  = "ubuntu-24-04-x64"
  name   = "bot"
  region = "ams3"
  size   = "s-1vcpu-1gb"
  ssh_keys = [
    data.digitalocean_ssh_key.skysome-key.id
  ]
}

/**
 * Firewall rules for the skysome droplet.
 * Any ports not specified are caught by a block-all rule.
 */
resource "digitalocean_firewall" "skysome-server-firewall" {
  name = "block-port-access"

  # The droplet that the firewall is tied to
  droplet_ids = [digitalocean_droplet.skysome-server.id]

  # Inbound SSH rule for Github Actions runner
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = [var.runner_ip_address]
  }

  # Inbound HTTPS rule allowing all access
  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0"]
  }

  # Outbound TCP rule allowing all access (for Discord text)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Outbound UDP rule allowing all access (for Discord audio/video)
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Outbound ICMP rule allowing all access
  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

/**
 * The IP address of skysome's droplet.
 */
output "droplet-ip-address" {
  value      = digitalocean_droplet.skysome-server.ipv4_address
}