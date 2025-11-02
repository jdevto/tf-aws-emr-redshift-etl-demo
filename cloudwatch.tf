# CloudWatch Log Groups

# EMR Serverless Log Group (WIRED - configured in outputs.tf)
resource "aws_cloudwatch_log_group" "emr_serverless" {
  name              = "/aws/emr-serverless/${local.name_prefix}-spark-app"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-emr-serverless-logs"
  })
}

resource "aws_cloudwatch_log_group" "redshift_connectionlog" {
  name              = "/aws/redshift/${local.name_prefix}-namespace/connectionlog"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redshift-connectionlog"
  })
}

resource "aws_cloudwatch_log_group" "redshift_useractivitylog" {
  name              = "/aws/redshift/${local.name_prefix}-namespace/useractivitylog"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redshift-useractivitylog"
  })
}
