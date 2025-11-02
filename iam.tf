# EMR Serverless execution role with least privilege policies
resource "aws_iam_role" "emr_serverless_execution" {
  name = "${local.name_prefix}-emr-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "emr-serverless.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-emr-execution-role"
  })
}

resource "aws_iam_role_policy" "emr_serverless_execution" {
  name = "${local.name_prefix}-emr-execution-policy"
  role = aws_iam_role.emr_serverless_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadScripts"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = ["${aws_s3_bucket.data.arn}/${local.s3_scripts_prefix}*"]
      },
      {
        Sid    = "S3ReadRaw"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = ["${aws_s3_bucket.data.arn}/${local.s3_raw_prefix}*"]
      },
      {
        Sid    = "S3ListBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [aws_s3_bucket.data.arn]
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "${local.s3_scripts_prefix}*",
              "${local.s3_raw_prefix}*",
              "${local.s3_curated_prefix}*",
              "${local.s3_logs_prefix}*"
            ]
          }
        }
      },
      {
        Sid    = "S3WriteCurated"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = ["${aws_s3_bucket.data.arn}/${local.s3_curated_prefix}*"]
      },
      {
        Sid    = "RedshiftDataAPIAccess"
        Effect = "Allow"
        Action = [
          "redshift-data:ExecuteStatement",
          "redshift-data:DescribeStatement",
          "redshift-data:GetStatementResult"
        ]
        Resource = "*"
      },
      {
        Sid    = "RedshiftServerlessGetCredentials"
        Effect = "Allow"
        Action = [
          "redshift-serverless:GetCredentials",
          "redshift-serverless:GetWorkgroup"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3WriteLogs"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = ["${aws_s3_bucket.data.arn}/${local.s3_logs_prefix}*"]
      },
      {
        Sid    = "CloudWatchLogsDescribe"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "*",
          "${aws_cloudwatch_log_group.emr_serverless.arn}",
          "${replace(aws_cloudwatch_log_group.emr_serverless.arn, ":*", "")}"
        ]
      },
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.emr_serverless.arn}:*",
          "${aws_cloudwatch_log_group.emr_serverless.arn}:*:*"
        ]
      },
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [aws_iam_role.emr_serverless_execution.arn]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "emr-serverless.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Additional KMS permissions if KMS is enabled
resource "aws_iam_role_policy" "emr_serverless_kms" {
  count = var.enable_kms ? 1 : 0
  name  = "${local.name_prefix}-emr-kms-policy"
  role  = aws_iam_role.emr_serverless_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KMSDecryptS3"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = [aws_kms_key.s3[0].arn]
      }
    ]
  })
}

# IAM role for Redshift namespace
resource "aws_iam_role" "redshift_namespace" {
  name = "${local.name_prefix}-redshift-namespace-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "redshift-serverless.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redshift-namespace-role"
  })
}

# IAM policy for Redshift namespace to write CloudWatch logs
resource "aws_iam_role_policy" "redshift_namespace_logs" {
  name = "${local.name_prefix}-redshift-namespace-logs-policy"
  role = aws_iam_role.redshift_namespace.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.redshift_connectionlog.arn}:*",
          "${aws_cloudwatch_log_group.redshift_connectionlog.arn}:*:*",
          "${aws_cloudwatch_log_group.redshift_useractivitylog.arn}:*",
          "${aws_cloudwatch_log_group.redshift_useractivitylog.arn}:*:*"
        ]
      }
    ]
  })
}
