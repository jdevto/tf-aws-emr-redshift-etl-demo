# Glue Data Catalog Database
resource "aws_glue_catalog_database" "curated" {
  name        = "${local.name_prefix}_curated"
  description = "Database for curated Parquet tables"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}_curated"
  })
}
