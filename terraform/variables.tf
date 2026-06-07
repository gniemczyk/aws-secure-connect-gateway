variable "vpc_id" {
  description = "ID of existing VPC"
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-z0-9]+$", var.vpc_id))
    error_message = "VPC ID must be in format: vpc-xxxxxxxx"
  }
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "eu-central-1"
}

variable "bastion_name" {
  description = "Bastion name (used as resource prefix)"
  type        = string
  default     = "ephemeral-bastion"
}

variable "container_image" {
  description = "Container image URI from ECR"
  type        = string
}
