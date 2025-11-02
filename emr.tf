# EMR Serverless Application
resource "aws_emrserverless_application" "spark" {
  name          = "${local.name_prefix}-spark-app"
  release_label = data.aws_emr_release_labels.latest.release_labels[0]
  type          = "SPARK"

  initial_capacity {
    initial_capacity_type = "Driver"
    initial_capacity_config {
      worker_count = 1
      worker_configuration {
        cpu    = "4 vCPU"
        memory = "16 GB"
      }
    }
  }

  maximum_capacity {
    cpu    = "200 vCPU"
    memory = "800 GB"
  }

  auto_start_configuration {
    enabled = true
  }

  auto_stop_configuration {
    enabled              = true
    idle_timeout_minutes = 15
  }

  network_configuration {
    subnet_ids         = aws_subnet.public[*].id
    security_group_ids = [aws_security_group.emr_serverless.id]
  }

  # Monitoring and logging configuration
  monitoring_configuration {
    # AWS managed persistence - 30 day retention
    managed_persistence_monitoring_configuration {
      enabled = true
    }

    # S3 logging configuration
    s3_monitoring_configuration {
      log_uri = "s3://${aws_s3_bucket.data.id}/${local.s3_logs_prefix}"
    }

    # CloudWatch logging configuration
    cloudwatch_logging_configuration {
      enabled                = true
      log_group_name         = aws_cloudwatch_log_group.emr_serverless.name
      log_stream_name_prefix = "emr-serverless-"

      # Log types to capture - driver logs
      log_types {
        name   = "SPARK_DRIVER"
        values = ["STDOUT", "STDERR"]
      }

      # Log types to capture - executor logs
      log_types {
        name   = "SPARK_EXECUTOR"
        values = ["STDOUT", "STDERR"]
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-spark-app"
  })
}
