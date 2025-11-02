# S3 Bucket
resource "aws_s3_bucket" "data" {
  bucket        = "${local.name_prefix}-data"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-data"
  })
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms ? aws_kms_key.s3[0].arn : null
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Sample data uploads
resource "aws_s3_object" "sample_data" {
  for_each = fileset("${path.module}/data/raw", "**")
  bucket   = aws_s3_bucket.data.id
  key      = "${local.s3_raw_prefix}${each.value}"
  source   = "${path.module}/data/raw/${each.value}"
  etag     = filemd5("${path.module}/data/raw/${each.value}")

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sample-data-${each.value}"
  })
}

# Spark job script upload
resource "aws_s3_object" "spark_script" {
  bucket = aws_s3_bucket.data.id
  key    = "${local.s3_scripts_prefix}etl_job.py"
  source = "${path.module}/spark_job/etl_job.py"
  etag   = filemd5("${path.module}/spark_job/etl_job.py")

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-spark-script"
  })
}

# No JDBC driver needed - using Redshift Data API instead
