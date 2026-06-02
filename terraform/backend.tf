# Terraform backend and required providers configuration

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket         = "secure-connect-gateway-tfstate"
    key            = "terraform.tfstate"
    region         = "eu-north-1"
    encrypt        = true
  }
}
