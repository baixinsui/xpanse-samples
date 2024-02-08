variable "flavor_id" {
  type        = string
  default     = "s6.large.2"
  description = "The flavor_id of the compute."
}

variable "image_name" {
  type        = string
  default     = "Ubuntu 22.04 server 64bit"
  description = "The image name of the compute."
}

variable "admin_passwd" {
  type        = string
  default     = ""
  description = "The root password of the compute."
}

variable "vpc_name" {
  type        = string
  default     = "ecs-vpc-default"
  description = "The vpc name of the compute."
}

variable "subnet_name" {
  type        = string
  default     = "ecs-subnet-default"
  description = "The subnet name of the compute."
}

variable "secgroup_name" {
  type        = string
  default     = "ecs-secgroup-default"
  description = "The security group name of the compute."
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
  admin_passwd = var.admin_passwd == "" ? random_password.password.result : var.admin_passwd
  vpc_id       = length(data.huaweicloud_vpcs.existing.vpcs) > 0 ? data.huaweicloud_vpcs.existing.vpcs[0].id : huaweicloud_vpc.new[0].id
  subnet_id    = length(data.huaweicloud_vpc_subnets.existing.subnets)> 0 ? data.huaweicloud_vpc_subnets.existing.subnets[0].id : huaweicloud_vpc_subnet.new[0].id
  secgroup_id  = length(data.huaweicloud_networking_secgroups.existing.security_groups) > 0 ? data.huaweicloud_networking_secgroups.existing.security_groups[0].id : huaweicloud_networking_secgroup.new[0].id
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
  description = "Kafka cluster security group"
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
  port_range_min    = 8080
  port_range_max    = 8088
  remote_ip_prefix  = "121.37.117.211/32"
  security_group_id = local.secgroup_id
}

resource "huaweicloud_networking_secgroup_rule" "secgroup_rule_2" {
  count             = length(data.huaweicloud_networking_secgroups.existing.security_groups) == 0 ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9090
  port_range_max    = 9099
  remote_ip_prefix  = "121.37.117.211/32"
  security_group_id = local.secgroup_id
}

data "huaweicloud_availability_zones" "osc-az" {}

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
  name     = "keypair-ecs-${random_id.new.hex}"
  key_file = "keypair-ecs-${random_id.new.hex}.pem"
}

data "huaweicloud_images_image" "image" {
  name        = var.image_name
  most_recent = true
}

resource "huaweicloud_compute_instance" "ecs-tf" {
  availability_zone  = data.huaweicloud_availability_zones.osc-az.names[0]
  name               = "ecs-tf-${random_id.new.hex}"
  flavor_id          = var.flavor_id
  security_group_ids = [ local.secgroup_id ]
  image_id           = data.huaweicloud_images_image.image.id
  key_pair           = huaweicloud_kps_keypair.keypair.name
  admin_pass       = local.admin_passwd
  network {
    uuid = local.subnet_id
  }
}

resource "huaweicloud_evs_volume" "volume" {
  name              = "volume-${random_id.new.hex}"
  description       = "my volume"
  volume_type       = "SSD"
  size              = 40
  availability_zone = data.huaweicloud_availability_zones.osc-az.names[0]
  tags = {
    foo = "bar"
    key = "value"
  }
}

resource "huaweicloud_compute_volume_attach" "attached" {
  instance_id = huaweicloud_compute_instance.ecs-tf.id
  volume_id   = huaweicloud_evs_volume.volume.id
}

resource "huaweicloud_vpc_eip" "myeip" {
  publicip {
    type = "5_sbgp"
  }
  bandwidth {
    name        = "mybandwidth"
    size        = 5
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

resource "huaweicloud_compute_eip_associate" "associated" {
  public_ip   = huaweicloud_vpc_eip.myeip.address
  instance_id = huaweicloud_compute_instance.ecs-tf.id
}

output "ecs-host" {
  value = huaweicloud_compute_instance.ecs-tf.access_ip_v4
}

output "ecs-public-ip" {
  value = huaweicloud_vpc_eip.myeip.address
}

output "admin_passwd" {
  value = var.admin_passwd == "" ? nonsensitive(local.admin_passwd) : local.admin_passwd
}
