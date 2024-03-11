variable "region" {
  type        = string
  description = "The region to deploy the Kafka cluster instance."
}

variable "availability_zone" {
  type        = string
  description = "The availability zone to deploy the Kafka cluster instance."
}

variable "flavor_id" {
  type        = string
  default     = "s6.large.2"
  description = "The flavor_id of all nodes in the Kafka cluster instance."
}

variable "image_name" {
  type        = string
  default     = "OBS Ubuntu 22.04"
  description = "The image name of the compute instance."
}

variable "worker_nodes_count" {
  type        = string
  default     = 3
  description = "The worker nodes count in the Kafka cluster instance."
}

variable "admin_passwd" {
  type= string
  default = ""
  description = "The root password of all nodes in the Kafka cluster instance."
}

variable "vpc_name" {
  type        = string
  default     = "kafka-vpc-default"
  description = "The vpc name of all nodes in the Kafka cluster instance."
}

variable "subnet_name" {
  type        = string
  default     = "kafka-subnet-default"
  description = "The subnet name of all nodes in the Kafka cluster instance."
}

variable "secgroup_name" {
  type        = string
  default     = "kafka-secgroup-default"
  description = "The security group name of all nodes in the Kafka cluster instance."
}

terraform {
  required_providers {
    flexibleengine = {
      source  = "FlexibleEngineCloud/flexibleengine"
      version = "~> 1.45.0"
    }
  }
}

provider "flexibleengine" {
  region = var.region
}

data "flexibleengine_availability_zones" "osc-az" {}

data "flexibleengine_vpc_v1" "existing" {
  name  = var.vpc_name
  count = length(data.flexibleengine_vpc_v1.existing)
}

data "flexibleengine_vpc_subnet_v1" "existing" {
  name  = var.subnet_name
  count = length(data.flexibleengine_vpc_subnet_v1.existing)
}

data "flexibleengine_networking_secgroup_v2" "existing" {
  name  = var.secgroup_name
  count = length(data.flexibleengine_networking_secgroup_v2.existing)
}

locals {
  availability_zone = var.availability_zone == "" ? data.flexibleengine_availability_zones.osc-az.names[0] : var.availability_zone
  admin_passwd      = var.admin_passwd == "" ? random_password.password.result : var.admin_passwd
  vpc_id            = length(data.flexibleengine_vpc_v1.existing) > 0 ? data.flexibleengine_vpc_v1.existing[0].id : flexibleengine_vpc_v1.new[0].id
  subnet_id         = length(data.flexibleengine_vpc_subnet_v1.existing) > 0 ? data.flexibleengine_vpc_subnet_v1.existing[0].id : flexibleengine_vpc_subnet_v1.new[0].id
  secgroup_id       = length(data.flexibleengine_networking_secgroup_v2.existing) > 0 ? data.flexibleengine_networking_secgroup_v2.existing[0].id : flexibleengine_networking_secgroup_v2.new[0].id
  secgroup_name     = length(data.flexibleengine_networking_secgroup_v2.existing) > 0 ? data.flexibleengine_networking_secgroup_v2.existing[0].name : flexibleengine_networking_secgroup_v2.new[0].name
}

resource "flexibleengine_vpc_v1" "new" {
  count = length(data.flexibleengine_vpc_v1.existing) == 0 ? 1 : 0
  name  = "${var.vpc_name}-${random_id.new.hex}"
  cidr  = "192.168.0.0/16"
}

resource "flexibleengine_vpc_subnet_v1" "new" {
  count      = length(data.flexibleengine_vpc_subnet_v1.existing) == 0 ? 1 : 0
  vpc_id     = local.vpc_id
  name       = "${var.subnet_name}-${random_id.new.hex}"
  cidr       = "192.168.10.0/24"
  gateway_ip = "192.168.10.1"
  dns_list   = ["100.125.0.41","100.125.12.161"]
}

resource "flexibleengine_networking_secgroup_v2" "new" {
  count       = length(data.flexibleengine_networking_secgroup_v2.existing) == 0 ? 1 : 0
  name        = "${var.secgroup_name}-${random_id.new.hex}"
  description = "Kafka cluster security group"
}

resource "flexibleengine_networking_secgroup_rule_v2" "secgroup_rule_0" {
  count             = length(data.flexibleengine_networking_secgroup_v2.existing) == 0 ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "121.37.117.211/32"
  security_group_id = local.secgroup_id
}

resource "flexibleengine_networking_secgroup_rule_v2" "secgroup_rule_1" {
  count             = length(data.flexibleengine_networking_secgroup_v2.existing) == 0 ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 2181
  port_range_max    = 2181
  remote_ip_prefix  = "121.37.117.211/32"
  security_group_id = local.secgroup_id
}

resource "flexibleengine_networking_secgroup_rule_v2" "secgroup_rule_2" {
  count             = length(data.flexibleengine_networking_secgroup_v2.existing) == 0 ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9092
  port_range_max    = 9093
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

resource "flexibleengine_compute_keypair_v2" "keypair" {
  name = "keypair-k8s-${random_id.new.hex}"
}

data "flexibleengine_images_image" "image" {
  name_regex  = "^${var.image_name}"
  most_recent = true
}

resource "flexibleengine_compute_instance_v2" "zookeeper" {
  availability_zone  = local.availability_zone
  name               = "kafka-zookeeper-${random_id.new.hex}"
  flavor_id          = var.flavor_id
  security_groups    = [ local.secgroup_name ]
  image_id           = data.flexibleengine_images_image.image.id
  key_pair           = flexibleengine_compute_keypair_v2.keypair.name
  network {
    uuid = local.subnet_id
  }
  user_data = <<EOF
        #!bin/bash
        echo root:${local.admin_passwd} | sudo chpasswd
        sudo systemctl start docker
        sudo systemctl enable docker
        sudo docker run -d --name zookeeper-server --privileged=true -p 2181:2181 -e ALLOW_ANONYMOUS_LOGIN=yes bitnami/zookeeper:3.8.1
      EOF
}

resource "flexibleengine_compute_instance_v2" "kafka-broker" {
  count              = var.worker_nodes_count
  availability_zone  = local.availability_zone
  name               = "kafka-broker-${count.index}-${random_id.new.hex}"
  flavor_id          = var.flavor_id
  security_groups    = [ local.secgroup_name ]
  image_id           = data.flexibleengine_images_image.image.id
  key_pair           = flexibleengine_compute_keypair_v2.keypair.name
  network {
    uuid = local.subnet_id
  }
  user_data = <<EOF
        #!bin/bash
        echo root:${local.admin_passwd} | sudo chpasswd
        sudo systemctl start docker
        sudo systemctl enable docker
        private_ip=$(ifconfig | grep -A1 "eth0" | grep 'inet' | awk -F ' ' ' {print $2}'|awk ' {print $1}')
        sudo docker run -d --name kafka-server --restart always -p 9092:9092 -p 9093:9093  -e KAFKA_BROKER_ID=${count.index}  -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://$private_ip:9092 -e KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092 -e ALLOW_PLAINTEXT_LISTENER=yes -e KAFKA_CFG_ZOOKEEPER_CONNECT=${flexibleengine_compute_instance_v2.zookeeper.access_ip_v4}:2181 bitnami/kafka:3.3.2
      EOF
  depends_on = [
    flexibleengine_compute_instance_v2.zookeeper
  ]
}

output "zookeeper_server" {
  value = "${flexibleengine_compute_instance_v2.zookeeper.access_ip_v4}:2181"
}

output "admin_passwd" {
  value = var.admin_passwd == "" ? nonsensitive(local.admin_passwd) : local.admin_passwd
}