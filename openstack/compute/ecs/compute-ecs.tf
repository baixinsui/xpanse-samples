variable "region" {
  type        = string
  description = "The region to deploy the compute instance."
}

variable "availability_zone" {
  type        = string
  description = "The availability zone to deploy the compute instance."
}

variable "flavor_id" {
  type        = string
  default     = "cirros256"
  description = "The flavor_id of the compute instance."
}

variable "image_name" {
  type        = string
  default     = "cirros-0.5.2-x86_64-disk"
  description = "The image name of the compute instance."
}

variable "admin_passwd" {
  type        = string
  default     = ""
  description = "The root password of the compute instance."
}

variable "vpc_name" {
  type        = string
  default     = "ecs-vpc-default"
  description = "The vpc name of the compute instance."
}

variable "subnet_name" {
  type        = string
  default     = "ecs-subnet-default"
  description = "The subnet name of the compute instance."
}

variable "secgroup_name" {
  type        = string
  default     = "ecs-secgroup-default"
  description = "The security group name of the compute instance."
}

terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53.0"
    }
  }
}

#provider "openstack" {
#  region = var.region
#}

data "openstack_compute_availability_zones_v2" "osc-az" {}

data "openstack_networking_network_v2" "existing" {
  name  = var.vpc_name
  count = length(data.openstack_networking_network_v2.existing)
}

data "openstack_networking_subnet_v2" "existing" {
  name  = var.subnet_name
  count = length(data.openstack_networking_subnet_v2.existing)
}

data "openstack_networking_secgroup_v2" "existing" {
  name  = var.secgroup_name
  count = length(data.openstack_networking_secgroup_v2.existing)
}

locals {
  availability_zone = var.availability_zone == "" ? data.openstack_compute_availability_zones_v2.osc-az.names[0] : var.availability_zone
  admin_passwd      = var.admin_passwd == "" ? random_password.password.result : var.admin_passwd
  vpc_id            = length(data.openstack_networking_network_v2.existing) > 0 ? data.openstack_networking_network_v2.existing[0].id : openstack_networking_network_v2.new[0].id
  subnet_id         = length(data.openstack_networking_subnet_v2.existing) > 0 ? data.openstack_networking_subnet_v2.existing[0].id : openstack_networking_subnet_v2.new[0].id
  secgroup_id       = length(data.openstack_networking_secgroup_v2.existing) > 0 ? data.openstack_networking_secgroup_v2.existing[0].id : openstack_networking_secgroup_v2.new[0].id
  secgroup_name     = length(data.openstack_networking_secgroup_v2.existing) > 0 ? data.openstack_networking_secgroup_v2.existing[0].name : openstack_networking_secgroup_v2.new[0].name
}

resource "openstack_networking_network_v2" "new" {
  count = length(data.openstack_networking_network_v2.existing) == 0 ? 1 : 0
  name  = "${var.vpc_name}-${random_id.new.hex}"
}

resource "openstack_networking_subnet_v2" "new" {
  count      = length(data.openstack_networking_subnet_v2.existing) == 0 ? 1 : 0
  network_id     = local.vpc_id
  name       = "${var.subnet_name}-${random_id.new.hex}"
  cidr       = "192.168.10.0/24"
  gateway_ip = "192.168.10.1"
}

resource "openstack_networking_secgroup_v2" "new" {
  count       = length(data.openstack_networking_secgroup_v2.existing) == 0 ? 1 : 0
  name        = "${var.secgroup_name}-${random_id.new.hex}"
  description = "Compute security group"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_0" {
  count             = length(data.openstack_networking_secgroup_v2.existing) == 0 ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "121.37.117.211/32"
  security_group_id = local.secgroup_id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_1" {
  count             = length(data.openstack_networking_secgroup_v2.existing) == 0 ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8080
  port_range_max    = 8088
  remote_ip_prefix  = "121.37.117.211/32"
  security_group_id = local.secgroup_id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_2" {
  count             = length(data.openstack_networking_secgroup_v2.existing) == 0 ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9090
  port_range_max    = 9099
  remote_ip_prefix  = "121.37.117.211/32"
  security_group_id = local.secgroup_id
}

resource "random_id" "new" {
  byte_length = 4
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

resource "openstack_compute_keypair_v2" "keypair" {
  name = "keypair-ecs-${random_id.new.hex}"
}

data "openstack_images_image_v2" "image" {
  name_regex  = "^${var.image_name}"
  most_recent = true
}

resource "openstack_compute_instance_v2" "ecs-tf" {
  availability_zone  = local.availability_zone
  name               = "ecs-tf-${random_id.new.hex}"
  flavor_id          = var.flavor_id
  security_groups    = [ local.secgroup_name ]
  image_id           = data.openstack_images_image_v2.image.id
  key_pair           = openstack_compute_keypair_v2.keypair.name
  admin_pass         = local.admin_passwd
  network {
    uuid = local.vpc_id
  }
}

resource "openstack_blockstorage_volume_v3" "volume" {
  name              = "volume-tf-${random_id.new.hex}"
  description       = "my volume"
  size              = 40
  availability_zone = local.availability_zone
}

resource "openstack_compute_volume_attach_v2" "attached" {
  instance_id = openstack_compute_instance_v2.ecs-tf.id
  volume_id   = openstack_blockstorage_volume_v3.volume.id
}

resource "openstack_networking_floatingip_v2" "myip" {
  pool = "my_pool"
}

resource "openstack_compute_floatingip_associate_v2" "myip" {
  floating_ip = openstack_networking_floatingip_v2.myip.address
  instance_id = openstack_compute_instance_v2.ecs-tf.id
  fixed_ip    = openstack_compute_instance_v2.ecs-tf.network.1.fixed_ip_v4
}

output "ecs-host" {
  value = openstack_compute_instance_v2.ecs-tf.access_ip_v4
}

output "ecs-public-ip" {
  value = openstack_networking_floatingip_v2.myip.address
}

output "admin_passwd" {
  value = var.admin_passwd == "" ? nonsensitive(local.admin_passwd) : local.admin_passwd
}
