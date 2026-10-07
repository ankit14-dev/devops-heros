variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "owner" {
  type    = string
  default = "ankit-kumar"
}

variable "name" {
  type    = string
  default = "taskboard"
}

variable "vpc_cidr" {
  type    = string
  default = "10.21.0.0/16"
}

variable "instance_type" {
  type        = string
  description = "t3.micro is free-tier eligible (1 GiB RAM + 2 GiB swap is enough for the dev profile)."
  default     = "t3.micro"
}

variable "image_tag" {
  type        = string
  description = "TaskBoard image tag in GHCR to deploy (a commit SHA published by the CI pipeline)."
  default     = "latest"
}

variable "git_ref" {
  type        = string
  description = "Branch/tag of the GitHub repo whose Helm chart is installed."
  default     = "main"
}
