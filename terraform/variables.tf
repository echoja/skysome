
variable "region" {
  default = "sgp1"
}

variable "do_token" {}
variable "github_token" {}
variable "github_username" {
  default     = "echoja"
  description = "GitHub username for the container registry"
}

variable "github_email" {
  default = "eszqsc112@gmail.com"
  description = "GitHub email for the container registry"
}

variable "spaces_access_key" {}
variable "spaces_secret_key" {}
variable "domain_name" {
  default     = "skysome.one"
  description = "Domain name to use for the app"
}
variable "email" {
  default     = "eszqsc112@gmail.com"
  description = "Email address to use for Let's Encrypt"
}

variable "web_image_tag" {
  default = "13"
}
