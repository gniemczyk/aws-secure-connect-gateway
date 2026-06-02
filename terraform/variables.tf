# Zmienne wejściowe dla konfiguracji Terraform

variable "vpc_id" {
  description = "ID istniejącego VPC w trybie Dual-Stack"
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-z0-9]+$", var.vpc_id))
    error_message = "VPC ID musi być w formacie: vpc-xxxxxxxx"
  }
}

variable "region" {
  description = "Region AWS"
  type        = string
  default     = "eu-central-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.region))
    error_message = "Region musi być poprawnym regionem AWS (np. eu-central-1)"
  }
}

variable "bastion_name" {
  description = "Nazwa bastionu (używana jako prefix zasobów)"
  type        = string
  default     = "ephemeral-bastion"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.bastion_name)) && length(var.bastion_name) <= 32
    error_message = "Nazwa może zawierać tylko małe litery, cyfry i myślniki, max 32 znaki"
  }
}

variable "container_image" {
  description = "URI obrazu kontenera z ECR"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9-]+:[a-z0-9]+$", var.container_image))
    error_message = "Container image musi być w formacie ECR: ACCOUNT.dkr.ecr.REGION.amazonaws.com/REPO:TAG"
  }
}

variable "serveo_subdomain" {
  description = "Subdomena Serveo.net dla tunelu (losowa jeśli nie podana)"
  type        = string
  default     = ""

  validation {
    condition     = var.serveo_subdomain == "" || can(regex("^[a-z0-9-]+$", var.serveo_subdomain)) && length(var.serveo_subdomain) <= 63
    error_message = "Subdomena może zawierać tylko małe litery, cyfry i myślniki, max 63 znaki"
  }
}
