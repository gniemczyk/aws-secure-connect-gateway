variable "vpc_id" {
  description = "ID istniejacego VPC"
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-z0-9]+$", var.vpc_id))
    error_message = "VPC ID must be in format: vpc-xxxxxxxx"
  }
}

variable "region" {
  description = "Region AWS"
  type        = string
  default     = "eu-central-1"
}

variable "bastion_name" {
  description = "Nazwa bastionu (uzywana jako prefiks zasobow)"
  type        = string
  default     = "ephemeral-bastion"
}

variable "container_image" {
  description = "URI obrazu kontenera z ECR"
  type        = string
}

variable "auto_stop_cron" {
  description = "Wyrazenie cron dla EventBridge Schedulera do automatycznego zatrzymywania bastionu"
  type        = string
  default     = "cron(0 23 * * ? *)"
}
