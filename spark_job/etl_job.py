#!/usr/bin/env python3
"""
EMR Serverless Spark ETL Job
Reads raw JSON from S3, joins with Redshift dim table, performs aggregations, and writes Parquet to S3
"""

import sys
import json
import boto3
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, sum as spark_sum, count, broadcast

def get_redshift_credentials(secret_arn, region_name=None):
    """Retrieve Redshift JDBC credentials from Secrets Manager"""
    try:
        # Get region from parameter, environment, or try to detect
        if not region_name:
            import os
            region_name = os.environ.get('AWS_DEFAULT_REGION') or os.environ.get('AWS_REGION')
            if not region_name:
                # Try to get from boto3 session
                try:
                    session = boto3.Session()
                    region_name = session.region_name
                except:
                    pass

        # Create client with region
        if region_name:
            secrets_client = boto3.client('secretsmanager', region_name=region_name)
        else:
            # Fallback: let boto3 try to detect (may fail in EMR)
            secrets_client = boto3.client('secretsmanager')

        response = secrets_client.get_secret_value(SecretId=secret_arn)
        secret = json.loads(response['SecretString'])
        return secret
    except Exception as e:
        raise Exception(f"Failed to retrieve Redshift credentials from Secrets Manager: {str(e)}")

def main():
    try:
        # Initialize Spark session
        spark = SparkSession.builder \
            .appName("EMR-Redshift-ETL") \
            .config("spark.sql.adaptive.enabled", "true") \
            .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
            .getOrCreate()

        # Get configuration from Spark conf
        raw_s3_path = spark.conf.get("spark.s3.raw.path")
        curated_s3_path = spark.conf.get("spark.s3.curated.path")
        redshift_db = spark.conf.get("spark.redshift.database")
        redshift_schema = spark.conf.get("spark.redshift.schema", "public")
        redshift_workgroup = spark.conf.get("spark.redshift.workgroup")
        aws_region = spark.conf.get("spark.aws.region")

        if not all([raw_s3_path, curated_s3_path, redshift_db, redshift_workgroup, aws_region]):
            missing = [k for k, v in {
                'raw_s3_path': raw_s3_path,
                'curated_s3_path': curated_s3_path,
                'redshift_db': redshift_db,
                'redshift_workgroup': redshift_workgroup,
                'aws_region': aws_region
            }.items() if not v]
            raise ValueError(f"Missing required Spark configuration parameters: {missing}")

        # Note: Redshift Data API uses IAM authentication - no credentials needed

        # Read raw JSON data from S3
        print(f"Reading raw data from: {raw_s3_path}")
        raw_df = spark.read.json(raw_s3_path)
        print(f"Raw data count: {raw_df.count()}")

        # Read dim table from Redshift via Data API (no direct network connection needed)
        # Redshift Data API uses AWS service endpoints, avoiding VPC networking issues
        dim_table_query = f"SELECT id, name, description FROM {redshift_schema}.dim_category"

        print(f"Reading dim table from Redshift: {redshift_schema}.dim_category")
        print(f"Using Redshift Data API with workgroup: {redshift_workgroup}")

        # Note: Redshift Data API uses IAM authentication - no credentials needed

        def query_redshift_data_api(query, workgroup, database, region_name):
            """Execute SQL query via Redshift Data API"""
            import time

            # Configure boto3 client with timeouts
            from botocore.config import Config
            config = Config(
                connect_timeout=60,
                read_timeout=60,
                retries={'max_attempts': 10, 'mode': 'adaptive'}
            )

            redshift_data_client = boto3.client('redshift-data', region_name=region_name, config=config)

            # Execute query
            try:
                response = redshift_data_client.execute_statement(
                    WorkgroupName=workgroup,
                    Database=database,
                    Sql=query
                )
                statement_id = response['Id']

                # Poll for completion
                max_attempts = 30
                for attempt in range(max_attempts):
                    time.sleep(2)
                    status_response = redshift_data_client.describe_statement(Id=statement_id)
                    status = status_response['Status']

                    if status == 'FINISHED':
                        # Get results
                        results = redshift_data_client.get_statement_result(Id=statement_id)
                        return results
                    elif status == 'FAILED':
                        error = status_response.get('Error', 'Unknown error')
                        raise Exception(f"Redshift query failed: {error}")
                    elif status in ['ABORTED', 'PICKED']:
                        # Continue polling
                        continue

                raise Exception(f"Query timed out after {max_attempts * 2} seconds")

            except Exception as e:
                raise Exception(f"Redshift Data API error: {str(e)}")

        try:
            print("Executing query via Redshift Data API...")
            results = query_redshift_data_api(
                query=dim_table_query,
                workgroup=redshift_workgroup,
                database=redshift_db,
                region_name=aws_region
            )

            # Convert results to Spark DataFrame
            from pyspark.sql.types import StructType, StructField, IntegerType, StringType
            from pyspark.sql import Row as SparkRow

            # Parse column metadata
            columns = results['ColumnMetadata']
            schema_fields = []
            for col_meta in columns:
                col_name = col_meta['name']
                col_type = col_meta['typeName']
                if col_type == 'int4':
                    schema_fields.append(StructField(col_name, IntegerType(), True))
                else:
                    schema_fields.append(StructField(col_name, StringType(), True))

            schema = StructType(schema_fields)

            # Parse rows
            rows = []
            for record in results['Records']:
                row_data = []
                for col_dict in record:
                    # Extract the actual value from the column dict
                    # Redshift Data API returns dict like {'longValue': 1} or {'stringValue': 'text'}
                    if col_dict:
                        # Get the first (and only) value from the dict
                        value = next(iter(col_dict.values()))
                    else:
                        value = None
                    row_data.append(value)
                rows.append(SparkRow(*row_data))

            # Create DataFrame
            dim_df = spark.createDataFrame(rows, schema)
            print("Redshift Data API query successful!")

        except Exception as api_error:
            error_msg = str(api_error)
            print(f"Redshift Data API failed: {error_msg[:500]}")
            raise Exception(f"Failed to query Redshift via Data API: {error_msg}")

        print(f"Dim table count: {dim_df.count()}")

        # Broadcast the small dim table for efficient join
        dim_df_broadcast = broadcast(dim_df)

        # Join raw data with dim table
        print("Performing broadcast join...")
        enriched_df = raw_df.join(
            dim_df_broadcast,
            raw_df.category_id == dim_df_broadcast.id,
            "inner"
        ).select(
            col("transaction_id"),
            col("amount"),
            col("date"),
            col("customer_id"),
            col("category_id"),
            col("name").alias("category_name"),
            col("description").alias("category_description")
        )

        # Perform aggregations
        print("Computing aggregations...")
        aggregated_df = enriched_df.groupBy("date", "category_id", "category_name") \
            .agg(
                spark_sum("amount").alias("total_amount"),
                count("transaction_id").alias("transaction_count")
            ) \
            .withColumnRenamed("date", "transaction_date") \
            .orderBy("transaction_date", "category_id")

        # Write Parquet to S3 curated path (partitioned by date)
        print(f"Writing Parquet to: {curated_s3_path}")
        aggregated_df.write \
            .mode("overwrite") \
            .partitionBy("transaction_date") \
            .option("compression", "snappy") \
            .parquet(curated_s3_path)

        print("ETL job completed successfully!")

        # Show sample results
        print("\nSample aggregated data:")
        aggregated_df.show(10, truncate=False)

        spark.stop()

    except Exception as e:
        print(f"ERROR: ETL job failed: {str(e)}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
