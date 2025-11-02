output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.data.id
}

output "s3_curated_path" {
  description = "S3 path for curated Parquet data"
  value       = "s3://${aws_s3_bucket.data.id}/${local.s3_curated_prefix}"
}

output "emr_application_id" {
  description = "EMR Serverless application ID"
  value       = aws_emrserverless_application.spark.id
}

output "aws_region" {
  description = "AWS region"
  value       = data.aws_region.current.id
}

output "redshift_endpoint" {
  description = "Redshift Serverless endpoint"
  value       = aws_redshiftserverless_workgroup.main.endpoint[0].address
}

output "redshift_workgroup_name" {
  description = "Redshift Serverless workgroup name"
  value       = aws_redshiftserverless_workgroup.main.workgroup_name
}

output "redshift_secret_arn" {
  description = "Secrets Manager secret ARN for Redshift credentials"
  value       = aws_secretsmanager_secret.redshift.arn
}

output "redshift_admin_password" {
  description = "Redshift admin password (generated randomly)"
  value       = random_password.redshift_admin.result
  sensitive   = true
}

output "emr_job_run_command" {
  description = "AWS CLI command to submit EMR Serverless job"
  value       = <<-EOT
    aws emr-serverless start-job-run \
      --region ${data.aws_region.current.id} \
      --application-id ${aws_emrserverless_application.spark.id} \
      --execution-role-arn ${aws_iam_role.emr_serverless_execution.arn} \
      --job-driver '{
        "sparkSubmit": {
          "entryPoint": "s3://${aws_s3_bucket.data.id}/${local.s3_scripts_prefix}etl_job.py",
          "sparkSubmitParameters": "--conf spark.s3.raw.path=s3://${aws_s3_bucket.data.id}/${local.s3_raw_prefix} --conf spark.s3.curated.path=s3://${aws_s3_bucket.data.id}/${local.s3_curated_prefix} --conf spark.redshift.database=${var.redshift_db_name} --conf spark.redshift.schema=${var.redshift_schema} --conf spark.redshift.workgroup=${var.redshift_workgroup_name} --conf spark.aws.region=${data.aws_region.current.id}"
        }
      }'
      # Note: Monitoring configuration (S3 and CloudWatch) is configured at the application level in emr.tf
      # Job-level configuration overrides are optional but not needed since app-level config applies to all jobs
  EOT
}

output "validate_command" {
  description = "Command to validate curated output"
  value       = "aws s3 ls s3://${aws_s3_bucket.data.id}/${local.s3_curated_prefix} --recursive"
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for monitoring (wired and actively used)"
  value = {
    emr_serverless           = aws_cloudwatch_log_group.emr_serverless.name
    redshift_connectionlog   = aws_cloudwatch_log_group.redshift_connectionlog.name
    redshift_useractivitylog = aws_cloudwatch_log_group.redshift_useractivitylog.name
  }
}

output "athena_workgroup_name" {
  description = "Athena workgroup name for querying curated data"
  value       = aws_athena_workgroup.curated.name
}

output "glue_database_name" {
  description = "Glue database name for curated data"
  value       = aws_glue_catalog_database.curated.name
}

output "glue_table_name" {
  description = "Glue table name for curated transactions"
  value       = aws_glue_catalog_table.curated_transactions.name
}
