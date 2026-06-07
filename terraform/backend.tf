# Terraform backend and required providers configuration

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configured via -backend-config flags in workflow
  # (allows dynamic region from GitHub variables)
  backend "s3" {
  }
}
