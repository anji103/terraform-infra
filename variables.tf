variable "aws_region" { type = string
default = "eu-north-1" }
variable "project_name" { type = string
default = "devops-practical" }
variable "environment" { type = string
default = "dev" }
variable "vpc_cidr" { type = string
default = "10.20.0.0/16" }
variable "instance_type" { type = string
default = "c7i-flex.large" }
variable "min_size" { type = number
default = 2 }
variable "desired_capacity" { type = number
default = 2 }
variable "max_size" { type = number
default = 4 }
variable "db_name" { type = string
default = "appdb" }
variable "db_username" { type = string
default = "appadmin" }
variable "db_instance_class" { type = string
default = "db.t3.micro" }
variable "db_allocated_storage" { type = number
default = 20 }
variable "db_multi_az" { type = bool
default = false }
variable "log_retention_days" { type = number
default = 90 }
 
data "aws_availability_zones" "available" {
  state = "available"
}
 
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
