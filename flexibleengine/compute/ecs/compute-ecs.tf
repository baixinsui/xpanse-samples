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
  default     = "s6.large.2"
  description = "The flavor_id of the compute instance."
}

variable "image_name" {
  type        = string
  default     = "OBS Ubuntu 22.04"
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
    flexibleengine = {
      source  = "FlexibleEngineCloud/flexibleengine"
      version = "~> 1.46.0"
    }
  }
}

provider "flexibleengine" {
  region = var.region
}

data "flexibleengine_availability_zones" "osc-az" {}

data "flexibleengine_vpcs" "existing" {
  name = var.vpc_name
}

resource "flexibleengine_vpc_v1" "new" {
  count = length(data.flexibleengine_vpcs.existing.vpcs) == 0 ? 1 : 0
  name  = "${var.vpc_name}-${random_id.new.hex}"
  cidr  = "192.168.0.0/16"
}

data "flexibleengine_vpc_subnets" "existing" {
  name = var.subnet_name
}

resource "flexibleengine_vpc_subnet_v1" "new" {
  count      = length(data.flexibleengine_vpc_subnets.existing.subnets) == 0 ? 1 : 0
  vpc_id     = local.vpc_id
  name       = "${var.subnet_name}-${random_id.new.hex}"
  cidr       = "192.168.10.0/24"
  gateway_ip = "192.168.10.1"
  dns_list   = ["100.125.0.41", "100.125.12.161"]
}

resource "flexibleengine_networking_secgroup_v2" "new" {
  name        = var.secgroup_name
  description = "Compute security group"
}

locals {
  availability_zone = var.availability_zone == "" ? data.flexibleengine_availability_zones.osc-az.names[0] : var.availability_zone
  admin_passwd      = var.admin_passwd == "" ? random_password.password.result : var.admin_passwd
  vpc_id            = length(data.flexibleengine_vpcs.existing.vpcs) > 0 ? data.flexibleengine_vpcs.existing.vpcs[0].id : flexibleengine_vpc_v1.new[0].id
  subnet_id         = length(data.flexibleengine_vpc_subnets.existing.subnets) > 0 ? data.flexibleengine_vpc_subnets.existing.subnets[0].id : flexibleengine_vpc_subnet_v1.new[0].id
  secgroup_id       = flexibleengine_networking_secgroup_v2.new.id
  secgroup_name     = flexibleengine_networking_secgroup_v2.new.name
}

resource "flexibleengine_networking_secgroup_rule_v2" "secgroup_rule_0" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "121.37.117.211/32"
  security_group_id = local.secgroup_id
}

resource "flexibleengine_networking_secgroup_rule_v2" "secgroup_rule_1" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8080
  port_range_max    = 8088
  remote_ip_prefix  = "121.37.117.211/32"
  security_group_id = local.secgroup_id
}

resource "flexibleengine_networking_secgroup_rule_v2" "secgroup_rule_2" {
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

data "flexibleengine_images_image" "image" {
  name                  = var.image_name
  most_recent           = true
  enterprise_project_id = "0"
}

resource "flexibleengine_compute_instance_v2" "ecs-tf" {
  availability_zone  = local.availability_zone
  name               = "ecs-terraform-${random_id.new.hex}"
  flavor_id          = var.flavor_id
  security_groups    = [ local.secgroup_name ]
  image_id           = data.flexibleengine_images_image.image.id
  network {
    uuid = local.subnet_id
  }
  user_data = <<EOF
      #!/bin/bash
      sudo sed -i 's/^#*PermitRootLogin.*$/PermitRootLogin yes/' /etc/ssh/sshd_config
      sudo sed -i 's/^#*PasswordAuthentication.*$/PasswordAuthentication yes/' /etc/ssh/sshd_config
      sudo systemctl restart ssh
      sudo echo "root:${local.admin_passwd}" | chpasswd
  EOF
}

resource "flexibleengine_blockstorage_volume_v2" "volume" {
  name              = "volume-tf-${random_id.new.hex}"
  description       = "my volume"
  volume_type       = "SSD"
  size              = 40
  availability_zone = local.availability_zone
  tags = {
    foo = "bar"
    key = "value"
  }
}

resource "flexibleengine_compute_volume_attach_v2" "attached" {
  instance_id = flexibleengine_compute_instance_v2.ecs-tf.id
  volume_id   = flexibleengine_blockstorage_volume_v2.volume.id
}

resource "flexibleengine_vpc_eip" "eip-tf" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    name        = "eip-tf-${random_id.new.hex}"
    size        = 5
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

resource "flexibleengine_compute_floatingip_associate_v2" "associated" {
  floating_ip = flexibleengine_vpc_eip.eip-tf.publicip.0.ip_address
  instance_id = flexibleengine_compute_instance_v2.ecs-tf.id
}

output "ecs-host" {
  value = flexibleengine_compute_instance_v2.ecs-tf.access_ip_v4
}

output "ecs-public-ip" {
  value = flexibleengine_vpc_eip.eip-tf.address
}

output "admin_passwd" {
  value = var.admin_passwd == "" ? nonsensitive(local.admin_passwd) : local.admin_passwd
}
