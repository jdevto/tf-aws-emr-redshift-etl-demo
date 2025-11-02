
# Secrets Manager for Redshift JDBC credentials
resource "aws_secretsmanager_secret" "redshift" {
  name                    = "${local.name_prefix}-redshift-credentials"
  recovery_window_in_days = 0
  description             = "Redshift JDBC connection credentials"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redshift-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "redshift" {
  secret_id = aws_secretsmanager_secret.redshift.id
  secret_string = jsonencode({
    host     = replace(aws_redshiftserverless_workgroup.main.endpoint[0].address, ":${aws_redshiftserverless_workgroup.main.endpoint[0].port}", "")
    port     = aws_redshiftserverless_workgroup.main.endpoint[0].port
    database = var.redshift_db_name
    username = var.redshift_admin_username
    password = random_password.redshift_admin.result
    jdbc_url = "jdbc:redshift://${replace(aws_redshiftserverless_workgroup.main.endpoint[0].address, ":${aws_redshiftserverless_workgroup.main.endpoint[0].port}", "")}:${aws_redshiftserverless_workgroup.main.endpoint[0].port}/${var.redshift_db_name}?SSL=true"
  })
}
