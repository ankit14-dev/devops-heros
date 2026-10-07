terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Credentials come from `aws configure` (~/.aws/credentials) - never hard-code keys here.
provider "aws" {
  region = var.aws_region

  # tags added to every resource this provider creates
  default_tags {
    tags = {
      Project   = "devops-heros-session18"
      Owner     = var.owner
      ManagedBy = "Terraform"
    }
  }
}
