# Data sources for dynamic values
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get latest EMR release label for Serverless
# release_labels are sorted with latest first
data "aws_emr_release_labels" "latest" {
  filters {
    prefix = "emr-" # EMR Serverless uses standard EMR release labels (e.g., emr-7.0.0)
  }
}

# Random password for Redshift admin user
resource "random_password" "redshift_admin" {
  length  = 20
  special = true
  upper   = true
  lower   = true
  numeric = true

  # Redshift password requirements:
  # - At least 8 characters (we use 20)
  # - Must contain at least one uppercase letter, one lowercase letter, and one number
  # - Can optionally include special characters: ! @ # $ % ^ & * ( ) _ + - =
  override_special = "!@#$%^&*()_+-="
}
