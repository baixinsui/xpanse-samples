variable "region" {
  type        = string
  default     = "cn-north-4"
  description = "The region to deploy the service instance."
}

variable "flavor_id" {
  type        = string
  default     = "s6.large.2"
  description = "The flavor id of the service instance."
}

variable "availability_zone" {
  type        = string
  default     = ""
  description = "The availability zone of the service instance."
}

variable "admin_passwd" {
  type        = string
  default     = ""
  description = "The root password of the service instance."
}

variable "vpc_name" {
  type        = string
  default     = "vpc-default"
  description = "The vpc name of the service instance."
}

variable "subnet_name" {
  type        = string
  default     = "subnet-default"
  description = "The subnet name of the service instance."
}

variable "secgroup_name" {
  type        = string
  default     = "secgroup-default"
  description = "The security group name of the service instance."
}

locals {
  admin_passwd = var.admin_passwd == "" ? random_password.password.result : var.admin_passwd
}

resource "random_password" "password" {
  length           = 12
  upper            = true
  lower            = true
  numeric          = true
  special          = true
  min_special      = 1
  override_special = "#%@"
}

output "flavor_id" {
  value = var.flavor_id
}

output "region" {
  value = var.region
}

output "availability_zone" {
  value = var.availability_zone == "" ? "" : var.availability_zone
}

output "vpc_name" {
  value = var.vpc_name
}

output "subnet_name" {
  value = var.subnet_name
}

output "secgroup_name" {
  value = var.secgroup_name
}

output "region_name" {
  value = var.region
}

output "admin_passwd" {
  value = var.admin_passwd == "" ? nonsensitive(local.admin_passwd) : local.admin_passwd
}
