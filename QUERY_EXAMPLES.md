# Query Examples for Curated Data

## Status Summary

✅ **Fully Tested and Working**:

- Athena SQL queries (Examples 1, 2, 3)
- Query status checking and result retrieval
- One-liner examples
- Local download with S3 sync

⚠️ **Requires Manual Setup**:

- PySpark jobs (requires new Spark script)
- Redshift loading (requires connection setup)
- QuickSight (requires UI configuration)
- External data warehouses (Snowflake, Databricks)
- Scheduled reports (requires Lambda function)

---

The curated Parquet files contain aggregated transaction data:

- `transaction_date` (partitioned)
- `category_id`
- `category_name`
- `total_amount` (sum of all transaction amounts)
- `transaction_count` (number of transactions)

## 1. Query with Athena (SQL) ✅ Tested and Working

Athena is already configured with a Glue table for easy SQL queries:

```bash
# Get region and workgroup
REGION=$(terraform output -raw aws_region)
WORKGROUP=$(terraform output -raw athena_workgroup_name)
DATABASE=$(terraform output -raw glue_database_name)
TABLE=$(terraform output -raw glue_table_name)

# Example 1: Total sales by category
QUERY_ID=$(aws athena start-query-execution \
  --region $REGION \
  --work-group $WORKGROUP \
  --query-string "
    SELECT
      category_name,
      SUM(total_amount) as total_sales,
      SUM(transaction_count) as total_transactions
    FROM \"$DATABASE\".\"$TABLE\"
    GROUP BY category_name
    ORDER BY total_sales DESC
  " \
  --result-configuration "OutputLocation=s3://$(terraform output -raw s3_bucket_name)/athena-results/" \
  --query 'QueryExecutionId' --output text)

# Check status (wait a few seconds for completion)
sleep 5
aws athena get-query-execution --query-execution-id $QUERY_ID --region $REGION \
  --query 'QueryExecution.Status.State' --output text

# Example 2: Daily sales trend
QUERY_ID=$(aws athena start-query-execution \
  --region $REGION \
  --work-group $WORKGROUP \
  --query-string "
    SELECT
      transaction_date,
      SUM(total_amount) as daily_total,
      SUM(transaction_count) as daily_transactions
    FROM \"$DATABASE\".\"$TABLE\"
    WHERE transaction_date >= DATE '2024-01-01'
    GROUP BY transaction_date
    ORDER BY transaction_date
  " \
  --result-configuration "OutputLocation=s3://$(terraform output -raw s3_bucket_name)/athena-results/" \
  --query 'QueryExecutionId' --output text)

# Example 3: Top category by month
QUERY_ID=$(aws athena start-query-execution \
  --region $REGION \
  --work-group $WORKGROUP \
  --query-string "
    SELECT
      DATE_TRUNC('month', transaction_date) as month,
      category_name,
      SUM(total_amount) as monthly_sales
    FROM \"$DATABASE\".\"$TABLE\"
    GROUP BY DATE_TRUNC('month', transaction_date), category_name
    ORDER BY month, monthly_sales DESC
  " \
  --result-configuration "OutputLocation=s3://$(terraform output -raw s3_bucket_name)/athena-results/" \
  --query 'QueryExecutionId' --output text)
```

## 2. Query with PySpark (Another EMR Job) ⚠️ Manual Setup Required

**Note**: This requires creating a new Spark job script and submitting it via EMR Serverless. See the main `spark_job/etl_job.py` as a reference.

You can create another Spark job to read and analyze the curated data:

```python
from pyspark.sql import SparkSession
from pyspark.sql.functions import *

spark = SparkSession.builder.appName("AnalyzeCurated").getOrCreate()

# Read curated Parquet
curated_path = "s3://your-bucket/curated/"
df = spark.read.parquet(curated_path)

# Analysis examples
df.show()

# Total sales by category
df.groupBy("category_name") \
  .agg(sum("total_amount").alias("total_sales")) \
  .orderBy(desc("total_sales")) \
  .show()

# Average transaction amount per category
df.withColumn("avg_amount", df.total_amount / df.transaction_count) \
  .groupBy("category_name") \
  .agg(avg("avg_amount").alias("avg_transaction")) \
  .show()
```

## 3. Load into Redshift for BI Tools ⚠️ Manual Setup Required

**Note**: Requires Redshift connection and IAM role configuration. The curated data is already in the same AWS account as your Redshift Serverless.

Load the curated data into Redshift for Business Intelligence tools:

```sql
-- In Redshift
COPY curated_transactions
FROM 's3://your-bucket/curated/'
IAM_ROLE 'arn:aws:iam::account:role/RedshiftRole'
FORMAT PARQUET;
```

Then query in Redshift or connect BI tools (Tableau, PowerBI, etc.)

## 4. Use with AWS QuickSight ⚠️ Manual UI Setup Required

**Steps**:

1. Go to AWS QuickSight console
2. Create a new dataset
3. Choose **Athena** as data source (recommended - uses the Glue table)
   - Database: `$(terraform output -raw glue_database_name)`
   - Table: `$(terraform output -raw glue_table_name)`
4. OR use **S3** direct access:
   - Point to: `s3://$(terraform output -raw s3_bucket_name)/curated/`
   - Select Parquet format
5. Build dashboards and visualizations

## 5. Download and Analyze Locally ✅ Tested and Working

```bash
# Download files
BUCKET=$(terraform output -raw s3_bucket_name)
aws s3 sync s3://$BUCKET/curated/ ./curated/

# Use Python with pandas/pyarrow
python3 -c "
import pandas as pd

# Read Parquet files (pandas handles directory automatically)
df = pd.read_parquet('./curated/')

# Analyze
print('Total rows:', len(df))
print('\nFirst 5 rows:')
print(df.head())
print('\nTotal sales by category:')
print(df.groupby('category_name')['total_amount'].sum().sort_values(ascending=False))
"
```

**Note**: Make sure you have `pandas` and `pyarrow` installed:

```bash
pip install pandas pyarrow
```

## 6. Load into Data Warehouses ⚠️ External Service Setup Required

### Snowflake

```sql
COPY INTO curated_transactions
FROM 's3://your-bucket/curated/'
STORAGE_INTEGRATION = your_s3_integration
FILE_FORMAT = (TYPE = PARQUET);
```

### Databricks

```python
df = spark.read.parquet("s3://your-bucket/curated/")
df.write.mode("overwrite").saveAsTable("curated_transactions")
```

## 7. Schedule Automated Reports ⚠️ Lambda Function Setup Required

**Note**: Requires creating a Lambda function with Athena query execution and result retrieval logic.

Use AWS Lambda + EventBridge to:

- Query Athena on schedule
- Email reports
- Update dashboards
- Trigger downstream processes

## Data Schema

The curated Parquet files have this schema:

| Column | Type | Description |
|--------|------|-------------|
| `transaction_date` | date | Partition key (YYYY-MM-DD) |
| `category_id` | int | Category ID from dim table |
| `category_name` | string | Category name (e.g., "Electronics") |
| `total_amount` | double | Sum of transaction amounts |
| `transaction_count` | bigint | Number of transactions |

## Performance Tips

1. **Partition Pruning**: Always filter by `transaction_date` for faster queries
2. **Columnar Format**: Parquet is columnar - only select needed columns
3. **Compression**: Files use Snappy compression (good balance)
4. **Projection**: Glue table uses partition projection for better performance

## Example: Complete Analytics Workflow

```bash
# 1. Run ETL job (creates curated data)
terraform output -raw emr_job_run_command | bash

# 2. Query with Athena
QUERY_ID=$(aws athena start-query-execution \
  --query-string "SELECT * FROM \"$(terraform output -raw glue_database_name)\".\"$(terraform output -raw glue_table_name)\" LIMIT 10" \
  --work-group $(terraform output -raw athena_workgroup_name) \
  --query 'QueryExecutionId' --output text)

# 3. Wait for completion
aws athena get-query-execution --query-execution-id $QUERY_ID \
  --query 'QueryExecution.Status.State' --output text

# 4. Get results
aws athena get-query-results --query-execution-id $QUERY_ID
```

## How to Check Query Status and Results ✅ All Tested and Working

### Quick Status Check

```bash
# Get region and query ID (from previous query execution)
REGION=$(terraform output -raw aws_region)
QUERY_ID="104646d9-452f-4c9d-94ad-6445ed44f5a8"  # Replace with your QueryExecutionId

# Check status
aws athena get-query-execution \
  --query-execution-id $QUERY_ID \
  --region $REGION \
  --query 'QueryExecution.Status.{State:State,StateChangeReason:StateChangeReason,SubmissionDateTime:SubmissionDateTime}' \
  --output json
```

### Wait for Completion (Polling)

```bash
REGION=$(terraform output -raw aws_region)
QUERY_ID="104646d9-452f-4c9d-94ad-6445ed44f5a8"  # Replace with your QueryExecutionId

# Poll until query completes
while true; do
  STATE=$(aws athena get-query-execution \
    --query-execution-id $QUERY_ID \
    --region $REGION \
    --query 'QueryExecution.Status.State' \
    --output text)

  echo "Query status: $STATE"

  if [ "$STATE" = "SUCCEEDED" ] || [ "$STATE" = "FAILED" ] || [ "$STATE" = "CANCELLED" ]; then
    break
  fi

  sleep 2
done
```

### Get Results (Once SUCCEEDED)

### Option 1: Get results as table (formatted)

```bash
REGION=$(terraform output -raw aws_region)
QUERY_ID="104646d9-452f-4c9d-94ad-6445ed44f5a8"  # Replace with your QueryExecutionId

aws athena get-query-results \
  --query-execution-id $QUERY_ID \
  --region $REGION \
  --output table
```

### Option 2: Get results as JSON (for parsing)

```bash
aws athena get-query-results \
  --query-execution-id $QUERY_ID \
  --region $REGION \
  --output json | jq '.ResultSet.Rows[2:] | .[] | .Data | map(.VarCharValue) | @csv'
```

### Option 3: Download results from S3 (recommended for large results)

```bash
# Get result location
RESULT_LOCATION=$(aws athena get-query-execution \
  --query-execution-id $QUERY_ID \
  --region $REGION \
  --query 'QueryExecution.ResultConfiguration.OutputLocation' \
  --output text)

echo "Results available at: $RESULT_LOCATION"

# Download results file
aws s3 cp "$RESULT_LOCATION" ./query-results.csv
```

### One-Liner: Run Query and Get Results

```bash
REGION=$(terraform output -raw aws_region)
WORKGROUP=$(terraform output -raw athena_workgroup_name)
DATABASE=$(terraform output -raw glue_database_name)
TABLE=$(terraform output -raw glue_table_name)

# Submit query and get ID
QUERY_ID=$(aws athena start-query-execution \
  --region $REGION \
  --work-group $WORKGROUP \
  --query-string "SELECT category_name, SUM(total_amount) as total_sales FROM \"$DATABASE\".\"$TABLE\" GROUP BY category_name ORDER BY total_sales DESC LIMIT 5" \
  --result-configuration "OutputLocation=s3://$(terraform output -raw s3_bucket_name)/athena-results/" \
  --query 'QueryExecutionId' \
  --output text)

echo "Query ID: $QUERY_ID"

# Wait for completion (max 30 seconds)
for i in {1..15}; do
  STATE=$(aws athena get-query-execution --query-execution-id $QUERY_ID --region $REGION --query 'QueryExecution.Status.State' --output text)
  if [ "$STATE" = "SUCCEEDED" ]; then
    echo "✅ Query succeeded!"
    aws athena get-query-results --query-execution-id $QUERY_ID --region $REGION --output table
    break
  elif [ "$STATE" = "FAILED" ]; then
    echo "❌ Query failed"
    aws athena get-query-execution --query-execution-id $QUERY_ID --region $REGION --query 'QueryExecution.Status.StateChangeReason' --output text
    break
  fi
  sleep 2
done
```
