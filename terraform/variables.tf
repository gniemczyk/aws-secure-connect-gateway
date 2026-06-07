variable "vpc_id" {
  description = "ID of existing VPC in Dual-Stack mode"
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

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.region))
    error_message = "Region must be valid AWS region (e.g. eu-central-1)"
  }
}

variable "bastion_name" {
  description = "Bastion name (used as resource prefix)"
  type        = string
  default     = "ephemeral-bastion"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.bastion_name)) && length(var.bastion_name) <= 32
    error_message = "Name can contain only lowercase letters, numbers and hyphens, max 32 characters"
  }
}

variable "container_image" {
  description = "Container image URI from ECR"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9-]+:[a-z0-9]+$", var.container_image))
    error_message = "Container image must be in ECR format: ACCOUNT.dkr.ecr.REGION.amazonaws.com/REPO:TAG"
  }
}

variable "bore_port" {
  description = "TCP port for bore.pub tunnel (random per workflow run)"
  type        = number

  validation {
    condition     = var.bore_port >= 1024 && var.bore_port <= 65535
    error_message = "Port must be between 1024 and 65535"
  }
}

variable "tfstate_bucket_region" {
  description = "Region where the Terraform state S3 bucket is located"
  type        = string
  default     = "eu-north-1"
}
