# Configure the OpenStack Provider
provider "openstack" {
  user_name   = var.user_name
  tenant_name = var.tenant_name
  password    = var.password
  auth_url    = var.auth_url
  region      = var.region
}

variable "user_name" {
  type = string
}

variable "password" {
  type = string
}

variable "tenant_name" {
  type = string
}

variable "auth_url" {
  type    = string
  default = "http://119.8.215.244/identity/v3"
}