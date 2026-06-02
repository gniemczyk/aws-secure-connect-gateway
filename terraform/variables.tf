# Zmienne wejściowe dla konfiguracji Terraform

variable "vpc_id" {
  description = "ID istniejącego VPC w trybie Dual-Stack"
  type        = string
}

variable "region" {
  description = "Region AWS"
  type        = string
  default     = "eu-central-1"
}

variable "bastion_name" {
  description = "Nazwa bastionu (używana jako prefix zasobów)"
  type        = string
  default     = "ephemeral-bastion"
}

variable "container_image" {
  description = "URI obrazu kontenera z ECR"
  type        = string
}

variable "serveo_subdomain" {
  description = "Subdomena Serveo.net dla tunelu (losowa jeśli nie podana)"
  type        = string
  default     = ""
}
