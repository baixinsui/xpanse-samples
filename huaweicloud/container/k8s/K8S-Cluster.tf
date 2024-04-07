variable "region" {
  type        = string
  description = "The region to deploy the K8S cluster instance."
}

variable "availability_zone" {
  type        = string
  description = "The availability zone to deploy the K8S cluster instance."
}

variable "flavor_id" {
  type        = string
  default     = "s6.large.2"
  description = "The flavor_id of all nodes in the K8S cluster instance."
}

variable "worker_nodes_count" {
  type        = string
  default     = 3
  description = "The worker nodes count in the K8S cluster instance."
}

variable "admin_passwd" {
  type        = string
  default     = ""
  description = "The root password of all nodes in the K8S cluster instance."
}

variable "vpc_name" {
  type        = string
  default     = "k8s-vpc-default"
  description = "The vpc name of all nodes in the K8S cluster instance."
}

variable "subnet_name" {
  type        = string
  default     = "k8s-subnet-default"
  description = "The subnet name of all nodes in the K8S cluster instance."
}

variable "secgroup_name" {
  type        = string
  default     = "k8s-secgroup-default"
  description = "The security group name of all nodes in the K8S cluster instance."
}

terraform {
  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.61.0"
    }
  }
}

provider "huaweicloud" {
  region = var.region
}

data "huaweicloud_availability_zones" "osc-az" {}

data "huaweicloud_vpcs" "existing" {
  name = var.vpc_name
}

data "huaweicloud_vpc_subnets" "existing" {
  name = var.subnet_name
}

data "huaweicloud_networking_secgroups" "existing" {
  name = var.secgroup_name
}

locals {
  availability_zone = var.availability_zone == "" ? data.huaweicloud_availability_zones.osc-az.names[0] : var.availability_zone
  admin_passwd      = var.admin_passwd == "" ? random_password.password.result : var.admin_passwd
  vpc_id            = length(data.huaweicloud_vpcs.existing.vpcs) > 0 ? data.huaweicloud_vpcs.existing.vpcs[0].id : huaweicloud_vpc.new[0].id
  subnet_id         = length(data.huaweicloud_vpc_subnets.existing.subnets)> 0 ? data.huaweicloud_vpc_subnets.existing.subnets[0].id : huaweicloud_vpc_subnet.new[0].id
  secgroup_id       = length(data.huaweicloud_networking_secgroups.existing.security_groups) > 0 ? data.huaweicloud_networking_secgroups.existing.security_groups[0].id : huaweicloud_networking_secgroup.new[0].id
}

resource "huaweicloud_vpc" "new" {
  count = length(data.huaweicloud_vpcs.existing.vpcs) == 0 ? 1 : 0
  name  = var.vpc_name
  cidr  = "192.168.0.0/16"
}

resource "huaweicloud_vpc_subnet" "new" {
  count      = length(data.huaweicloud_vpcs.existing.vpcs) == 0 ? 1 : 0
  vpc_id     = local.vpc_id
  name       = var.subnet_name
  cidr       = "192.168.10.0/24"
  gateway_ip = "192.168.10.1"
}

resource "huaweicloud_networking_secgroup" "new" {
  count       = length(data.huaweicloud_networking_secgroups.existing.security_groups) == 0 ? 1 : 0
  name        = var.secgroup_name
  description = "k8s cluster security group"
}

resource "huaweicloud_networking_secgroup_rule" "secgroup_rule_0" {
  count             = length(data.huaweicloud_networking_secgroups.existing.security_groups) == 0 ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
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

resource "huaweicloud_kps_keypair" "keypair" {
  name     = "keypair-k8s-${random_id.new.hex}"
  key_file = "keypair-kafka-${random_id.new.hex}.pem"
}

data "huaweicloud_images_image" "image" {
  name                  = "K8S-v1.26.2_Centos-7.9"
  most_recent           = true
  enterprise_project_id = "0"
}

resource "huaweicloud_compute_instance" "k8s-master" {
  availability_zone  = local.availability_zone
  name               = "k8s-master-${random_id.new.hex}"
  flavor_id          = var.flavor_id
  security_group_ids = [ local.secgroup_id ]
  image_id           = data.huaweicloud_images_image.image.id
  key_pair           = huaweicloud_kps_keypair.keypair.name
  network {
    uuid = local.subnet_id
  }
  user_data = <<EOF
        #!bin/bash
        echo root:${local.admin_passwd} | sudo chpasswd
        sudo sh /root/k8s-init.sh true ${local.admin_passwd} ${var.worker_nodes_count} > /root/init.log
      EOF
}

resource "huaweicloud_compute_instance" "k8s-node" {
  count              = var.worker_nodes_count
  availability_zone  = local.availability_zone
  name               = "k8s-node-${random_id.new.hex}-${count.index}"
  flavor_id          = var.flavor_id
  security_group_ids = [ local.secgroup_id ]
  image_id           = data.huaweicloud_images_image.image.id
  key_pair           = huaweicloud_kps_keypair.keypair.name
  network {
    uuid = local.subnet_id
  }
  user_data = <<EOF
        #!bin/bash
        echo root:${local.admin_passwd} | sudo chpasswd
        sudo sh /root/k8s-init.sh false ${local.admin_passwd} ${var.worker_nodes_count} ${huaweicloud_compute_instance.k8s-master.access_ip_v4} > /root/init.log
      EOF
  depends_on = [
    huaweicloud_compute_instance.k8s-master
  ]
}

output "k8s_master_host" {
  value = huaweicloud_compute_instance.k8s-master.access_ip_v4
}

output "admin_passwd" {
  value = var.admin_passwd == "" ? nonsensitive(local.admin_passwd) : local.admin_passwd
}
