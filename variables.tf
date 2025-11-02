variable "project_name" {
  description = "Prefix for resource names"
  type        = string
  default     = "emr-redshift-etl"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "redshift_db_name" {
  description = "Redshift database name"
  type        = string
  default     = "etldb"
}

variable "redshift_schema" {
  description = "Redshift schema name"
  type        = string
  default     = "public"
}

variable "redshift_workgroup_name" {
  description = "Redshift Serverless workgroup name"
  type        = string
  default     = "etl-workgroup"
}

variable "enable_kms" {
  description = "Enable KMS encryption"
  type        = bool
  default     = false
}

variable "redshift_base_capacity" {
  description = "Redshift Serverless base capacity in RPU"
  type        = number
  default     = 32
}

variable "redshift_admin_username" {
  description = "Redshift admin username"
  type        = string
  default     = "admin"
}
