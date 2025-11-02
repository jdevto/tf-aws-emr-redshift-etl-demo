locals {
  # Common naming
  name_prefix = "${var.project_name}-${var.environment}"

  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  # S3 paths
  s3_raw_prefix     = "raw/"
  s3_curated_prefix = "curated/"
  s3_scripts_prefix = "scripts/"
  s3_logs_prefix    = "logs/"
}
