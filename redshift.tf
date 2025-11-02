# Redshift Serverless Namespace
resource "aws_redshiftserverless_namespace" "main" {
  namespace_name = "${local.name_prefix}-namespace"
  db_name        = var.redshift_db_name

  iam_roles            = [aws_iam_role.redshift_namespace.arn]
  default_iam_role_arn = aws_iam_role.redshift_namespace.arn
  admin_username       = var.redshift_admin_username
  admin_user_password  = random_password.redshift_admin.result

  # Enable audit logging to CloudWatch
  # Redshift Serverless automatically sends logs to CloudWatch log group
  log_exports = ["connectionlog", "useractivitylog"]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-namespace"
  })
}

# Redshift Serverless Workgroup
resource "aws_redshiftserverless_workgroup" "main" {
  workgroup_name = var.redshift_workgroup_name
  namespace_name = aws_redshiftserverless_namespace.main.namespace_name

  base_capacity       = var.redshift_base_capacity
  publicly_accessible = true

  tags = merge(local.common_tags, {
    Name = var.redshift_workgroup_name
  })
}

# Redshift bootstrap SQL statements using Redshift Data API
resource "aws_redshiftdata_statement" "create_schema" {
  workgroup_name = aws_redshiftserverless_workgroup.main.workgroup_name
  database       = var.redshift_db_name

  sql = <<-SQL
    CREATE SCHEMA IF NOT EXISTS ${var.redshift_schema};
  SQL
}

resource "aws_redshiftdata_statement" "create_dim_table" {
  depends_on = [aws_redshiftdata_statement.create_schema]

  workgroup_name = aws_redshiftserverless_workgroup.main.workgroup_name
  database       = var.redshift_db_name

  sql = file("${path.module}/redshift/bootstrap.sql")
}
