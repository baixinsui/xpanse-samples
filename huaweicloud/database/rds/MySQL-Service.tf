variable "region" {
  type        = string
  default     = ""
  description = "The region to deploy the mysql service instance."
}

variable "primary_az" {
  type        = string
  default     = ""
  description = "The primary availability zone to deploy the mysql service instance."
}

variable "secondary_az" {
  type        = string
  default     = ""
  description = "The secondary availability zone to deploy the mysql service instance."
}

variable "flavor_id" {
  type        = string
  description = "The flavor_id of the mysql service instance."
}

variable "db_version" {
  type        = string
  default     = "8.0"
  description = "The version of the database to create in the mysql service instance."
}

variable "admin_passwd" {
  type        = string
  default     = ""
  description = "The root password of the mysql service instance."
}

variable "db_name" {
  type        = string
  default     = "test"
  description = "The database name to create in the mysql service instance."
}

variable "db_port" {
  type        = number
  default     = 3306
  description = "The port of the created database in the mysql service instance."
}

variable "user_name" {
  type        = string
  default     = "test"
  description = "The user name of the created database."
}

variable "vpc_name" {
  type        = string
  default     = "rds-vpc-default"
  description = "The vpc name of the mysql service instance."
}

variable "subnet_name" {
  type        = string
  default     = "rds-subnet-default"
  description = "The subnet name of the mysql service instance."
}

variable "secgroup_name" {
  type        = string
  default     = "rds-secgroup-default"
  description = "The security group name of the mysql service instance."
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

resource "huaweicloud_networking_secgroup_rule" "secgroup_rule_1" {
  count             = length(data.huaweicloud_networking_secgroups.existing.security_groups) == 0 ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = var.db_port
  port_range_max    = var.db_port
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

resource "huaweicloud_vpc_eip" "eip-tf" {
  publicip {
    type = "5_sbgp"
  }
  bandwidth {
    name        = "rds-tf-${random_id.new.hex}"
    size        = 5
    share_type  = "PER"
    charge_mode = "traffic"
  }
}


resource "huaweicloud_rds_instance" "instance" {
  name                = "rds-tf-${random_id.new.hex}"
  flavor              = var.flavor_id
  ha_replication_mode = "async"
  vpc_id              = local.vpc_id
  subnet_id           = local.subnet_id
  security_group_id   = local.secgroup_id
  availability_zone   = [
    var.primary_az,
    var.secondary_az]

  db {
    type     = "MySQL"
    version  = var.db_version
    password = local.admin_passwd
    port     = var.db_port
  }

  volume {
    type = "ESSD"
    size = 100
  }

  backup_strategy {
    start_time = "01:00-02:00"
    keep_days  = 1
  }

  parameters {
    name  = "lower_case_table_names"
    value = 1
  }
}

resource "huaweicloud_vpc_eip_associate" "associated" {
  public_ip  = huaweicloud_vpc_eip.eip-tf.address
  network_id = local.subnet_id
  fixed_ip   = huaweicloud_rds_instance.instance.fixed_ip
}

resource "huaweicloud_rds_mysql_database" "db" {
  instance_id   = huaweicloud_rds_instance.instance.id
  name          = var.db_name
  character_set = "utf8"
}

resource "huaweicloud_rds_mysql_account" "user" {
  instance_id = huaweicloud_rds_instance.instance.id
  name        = var.user_name
  password    = local.admin_passwd
}

resource "huaweicloud_rds_mysql_database_privilege" "privilege" {
  instance_id = huaweicloud_rds_instance.instance.id
  db_name     = var.db_name

  users {
    name     = var.user_name
    readonly = false
  }
}

resource "huaweicloud_rds_mysql_binlog" "test" {
  instance_id            = huaweicloud_rds_instance.instance.id
  binlog_retention_hours = 6
}

output "rds_instance_public_ips" {
  value = huaweicloud_vpc_eip.eip-tf.address
}

output "rds_instance_private_ips" {
  value = huaweicloud_rds_instance.instance.private_ips
}

output "admin_passwd" {
  value = var.admin_passwd == "" ? nonsensitive(local.admin_passwd) : local.admin_passwd
}