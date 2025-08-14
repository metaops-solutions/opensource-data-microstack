variable "instance_type" {
  description = "EC2 instance type for K3s node"
  type        = string
  default     = "t3.xlarge"
}

variable "root_disk_size" {
  description = "Root EBS volume size in GB for K3s node"
  type        = number
  default     = 100
}

variable "ssh_whitelist_cidrs" {
  description = "List of CIDR blocks allowed to SSH (port 22)"
  type        = list(string)
  default     = []
}

variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "eu-west-2"
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "k3s-vpc"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
}

variable "public_subnets" {
  description = "List of public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets" {
  description = "List of private subnet CIDRs"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "data_disks" {
  description = "List of data disk maps: { name, size, device_name }"
  type = list(object({
    name        = string
    size        = number
    device_name = string
  }))
  default = [
    { name = "k3s-data-disk", size = 100, device_name = "/dev/xvdb" }
    #    { name = "k3s-data-disk-2", size = 100, device_name = "/dev/xvdc" },
  ]
}
