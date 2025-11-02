# KMS Keys (only if enable_kms is true)
resource "aws_kms_key" "s3" {
  count = var.enable_kms ? 1 : 0

  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-key"
  })
}

resource "aws_kms_alias" "s3" {
  count = var.enable_kms ? 1 : 0

  name          = "alias/${local.name_prefix}-s3"
  target_key_id = aws_kms_key.s3[0].key_id
}

resource "aws_kms_key" "secrets" {
  count = var.enable_kms ? 1 : 0

  description             = "KMS key for Secrets Manager"
  deletion_window_in_days = 7
  enable_key_rotation     = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secrets-key"
  })
}

resource "aws_kms_alias" "secrets" {
  count = var.enable_kms ? 1 : 0

  name          = "alias/${local.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets[0].key_id
}
