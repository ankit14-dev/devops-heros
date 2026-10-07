variable "aws_region" {
  type        = string
  description = "AWS region where the S3 bucket is created."
  default     = "ap-south-1"
}

variable "bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name (lowercase, 3-63 chars)."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Bucket names must be 3-63 chars of lowercase letters, numbers, dots and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Environment tag (dev/stage/prod)."
  default     = "dev"
}

variable "owner" {
  type        = string
  description = "Who owns these resources (tag)."
}

variable "enable_versioning" {
  type        = bool
  description = "Keep old versions of objects."
  default     = true
}
