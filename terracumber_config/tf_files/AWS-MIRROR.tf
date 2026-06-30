# --- CONFIGURATION VARIABLES ---
variable "AWS_REGION" {
  type        = string
  default     = "eu-west-1"
  description = "The target AWS Region"
}

variable "AWS_AVAILABILITY_ZONE" {
  type        = string
  default     = "eu-west-1a"
  description = "The exact Availability Zone for the subnet and instance"
}

variable "NAME_PREFIX" {
  type        = string
  default     = "testing-mirror"
  description = "A prefix for all resource names to easily identify them in the AWS console"
}

variable "SSH_KEY" {
  type        = string
  default     = "testing-suma"
  description = "The exact name of the SSH Key Pair that already exists in your AWS account region"
}

variable "ALLOWED_IPS" {
  type    = list(string)
  default = []
}

provider "aws" {
  region = var.AWS_REGION
}


