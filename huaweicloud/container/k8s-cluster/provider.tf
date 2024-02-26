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

variable "region" {
  type        = string
  default     = "cn-southwest-2"
  description = "The region to deploy the service instance."
}