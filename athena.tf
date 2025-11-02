# Athena workgroup for querying curated data
resource "aws_athena_workgroup" "curated" {
  name = "${local.name_prefix}-curated-workgroup"

  configuration {
    enforce_workgroup_configuration    = false
    publish_cloudwatch_metrics_enabled = true
    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    result_configuration {
      output_location = "s3://${aws_s3_bucket.data.id}/athena-results/"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-curated-workgroup"
  })
}

# Glue table for curated Parquet data (for Athena queries)
resource "aws_glue_catalog_table" "curated_transactions" {
  name          = "curated_transactions"
  database_name = aws_glue_catalog_database.curated.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                                    = "TRUE"
    "parquet.compress"                          = "snappy"
    "projection.enabled"                        = "true"
    "projection.transaction_date.type"          = "date"
    "projection.transaction_date.format"        = "yyyy-MM-dd"
    "projection.transaction_date.range"         = "2024-01-01,2024-12-31"
    "projection.transaction_date.interval"      = "1"
    "projection.transaction_date.interval.unit" = "DAYS"
    "storage.location.template"                 = "s3://${aws_s3_bucket.data.id}/${local.s3_curated_prefix}transaction_date=$${transaction_date}/"
  }

  partition_keys {
    name = "transaction_date"
    type = "date"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data.id}/${local.s3_curated_prefix}"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "curated-transactions"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"

      parameters = {
        "serialization.format" = "1"
      }
    }

    columns {
      name = "category_id"
      type = "int"
    }
    columns {
      name = "category_name"
      type = "string"
    }
    columns {
      name = "total_amount"
      type = "double"
    }
    columns {
      name = "transaction_count"
      type = "bigint"
    }
  }
}
