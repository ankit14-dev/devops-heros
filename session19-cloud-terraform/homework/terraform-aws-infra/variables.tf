variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type        = string
  description = "Name prefix for all resources."
  default     = "devops-heros-s19"
}

variable "owner" {
  type    = string
  default = "ankit-kumar"
}

variable "vpc_cidr" {
  type    = string
  default = "10.19.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.19.1.0/24"
}

variable "instance_type" {
  type        = string
  description = "Free-tier eligible instance type."
  default     = "t3.micro"
}

variable "ssh_allowed_cidr" {
  type        = string
  description = "CIDR allowed to SSH. Empty = SSH closed (use EC2 Instance Connect / SSM instead)."
  default     = ""
}
