# Konfiguracja backendu Terraform
# Używamy lokalnego backendu dla uproszczenia w pipeline GitHub Actions
# Stan będzie przechowywany tymczasowo podczas wykonywania workflow

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}
