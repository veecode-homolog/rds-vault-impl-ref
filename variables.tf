variable "vault_address" {
    description = "url to use to access vault"
    default     = null
  }

variable "skip_final_snapshot" {
    description = "name database"
    default     = null
}

variable "db_password" {
  sensitive   = true
  default     = null
  
}

variable "aws_access_key" {
  description = "AWS Access Key ID."
  sensitive   = true
  default     = null

}

variable "aws_secret_key" {
  description = "AWS Access Secret Key."
  sensitive   = true
  default     = null

}

variable "aws_region" {
  description = "AWS Region."
  default     = null
}