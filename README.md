# EMR Redshift ETL Pipeline Demo

Complete Terraform-managed ETL pipeline: S3 Raw → EMR Serverless Spark → Redshift Serverless Dim Lookup → S3 Curated Parquet

## Architecture

```plaintext
S3 Raw (JSON)
    ↓
EMR Serverless Spark (with VPC for outbound connectivity)
    ↓ (Redshift Data API)
Redshift Serverless (dim_category lookup)
    ↓ (broadcast join)
Aggregations (group by date, category)
    ↓
S3 Curated (Parquet, partitioned by date)
    ↓
Athena queries (Glue Catalog table configured)
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- AWS account with permissions for:
  - EMR Serverless
  - Redshift Serverless
  - S3
  - IAM
  - Secrets Manager
  - Glue Data Catalog
  - KMS (optional)

## Quickstart

### 1. Configure Variables

Create a `terraform.tfvars` file:

```hcl
project_name = "emr-redshift-etl"
environment  = "dev"
# redshift_admin_password is auto-generated (minimum 20 chars with complexity)
```

### 2. Initialize and Apply Infrastructure

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Apply infrastructure (creates S3, Redshift, EMR, IAM, Secrets, Glue)
# Note: Redshift bootstrap (schema and dim table) is created automatically
terraform apply
```

### 3. Upload Sample Data and Spark Script

If sample data and Spark script weren't uploaded during `terraform apply`:

```bash
# Upload sample JSON files to S3 raw prefix
terraform apply -target=aws_s3_object.sample_data -auto-approve

# Upload Spark ETL job to S3 scripts prefix
terraform apply -target=aws_s3_object.spark_script -auto-approve
```

### 4. Run ETL Job

Submit the EMR Serverless job:

```bash
# Get region from Terraform
REGION=$(terraform output -raw aws_region)

# Submit job and extract job run ID
JOB_OUTPUT=$(terraform output -raw emr_job_run_command | sed "s/--region \${data\.aws_region\.current\.id}/--region $REGION/" | bash 2>&1)
JOB_RUN_ID=$(echo "$JOB_OUTPUT" | grep -oP 'jobRunId["\s:]*["\s]*\K[^"]+' || echo "$JOB_OUTPUT" | grep -oP '"id"\s*:\s*"\K[^"]+')

if [ -z "$JOB_RUN_ID" ]; then
    echo "❌ Failed to submit job or get job run ID"
    echo "$JOB_OUTPUT"
    exit 1
fi

echo "✅ Job submitted! Job Run ID: $JOB_RUN_ID"
```

**Wait for the job to complete** (typically 2-5 minutes).

Check job status:

```bash
# Get region and application ID from Terraform
REGION=$(terraform output -raw aws_region)
APP_ID=$(terraform output -raw emr_application_id)

# Check status
aws emr-serverless get-job-run \
  --application-id $APP_ID \
  --job-run-id $JOB_RUN_ID \
  --query 'jobRun.{state:state,stateDetails:stateDetails,updatedAt:updatedAt}' \
  --output json \
  --region $REGION
```

**Job states:** `SUBMITTED` → `RUNNING` → `SUCCESS` or `FAILED`

**If job failed**, check logs:

```bash
# View CloudWatch logs
aws logs tail $(terraform output -json | jq -r '.cloudwatch_log_groups.value.emr_serverless') \
  --region $REGION \
  --since 30m

# Or check S3 logs
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/logs/ --recursive | tail -10
```

### 5. Validate Output

**After job shows `SUCCESS`**, check curated Parquet files in S3:

```bash
terraform output -raw validate_command | bash
```

**Expected output:** Files like `curated/transaction_date=2024-01-15/part-*.parquet`

**If empty:**

- Job may still be running (check status above)
- Job may have failed (check logs below)
- Wait a few seconds for S3 eventual consistency

Or use the automated test script (waits for job completion):

```bash
./test.sh
```

### 6. Query Curated Data

Query the curated Parquet files using Athena or other methods. See **[QUERY_EXAMPLES.md](QUERY_EXAMPLES.md)** for complete examples:

**Quick Athena Query:**

```bash
REGION=$(terraform output -raw aws_region)
WORKGROUP=$(terraform output -raw athena_workgroup_name)
DATABASE=$(terraform output -raw glue_database_name)
TABLE=$(terraform output -raw glue_table_name)

# Example: Total sales by category
QUERY_ID=$(aws athena start-query-execution \
  --region $REGION \
  --work-group $WORKGROUP \
  --query-string "SELECT category_name, SUM(total_amount) as total_sales FROM \"$DATABASE\".\"$TABLE\" GROUP BY category_name ORDER BY total_sales DESC LIMIT 5" \
  --result-configuration "OutputLocation=s3://$(terraform output -raw s3_bucket_name)/athena-results/" \
  --query 'QueryExecutionId' --output text)

# Wait and get results
sleep 5
aws athena get-query-results --query-execution-id $QUERY_ID --region $REGION --output table
```

**For more query examples** including PySpark, local analysis, and BI tools integration, see [QUERY_EXAMPLES.md](QUERY_EXAMPLES.md).

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `project_name` | Prefix for resource names | `"emr-redshift-etl"` |
| `environment` | Environment name | `"dev"` |
| `redshift_db_name` | Redshift database name | `"etldb"` |
| `redshift_schema` | Redshift schema name | `"public"` |
| `redshift_workgroup_name` | Redshift workgroup name | `"etl-workgroup"` |
| `redshift_admin_username` | Redshift admin username | `"admin"` |
| `redshift_admin_password` | Redshift admin password | Auto-generated (20 chars, meets complexity) |
| `redshift_base_capacity` | Redshift base capacity (RPU) | `32` |
| `enable_kms` | Enable KMS encryption | `false` |

## Common Commands

**Infrastructure:**

- `terraform init` - Initialize Terraform
- `terraform validate` - Validate Terraform configuration
- `terraform plan` - Create Terraform plan
- `terraform apply` - Apply all infrastructure (includes Redshift bootstrap)
- `terraform apply -target=aws_s3_object.sample_data` - Upload sample data to S3
- `terraform apply -target=aws_s3_object.spark_script` - Upload Spark job script
- `terraform destroy` - Destroy all infrastructure

**ETL Operations:**

- `terraform output -raw emr_job_run_command | bash` - Submit EMR Serverless job
- `terraform output -raw validate_command | bash` - Validate curated output in S3
- `./test.sh` - Run automated end-to-end test

**Querying Data:**

- See [QUERY_EXAMPLES.md](QUERY_EXAMPLES.md) for complete examples including:
  - Athena SQL queries
  - Local analysis with pandas
  - BI tool integration
  - Data warehouse loading

## File Structure

```plaintext
.
├── main.tf              # Data sources, random password
├── s3.tf                # S3 bucket, sample data, Spark script upload
├── secret.tf            # Secrets Manager for Redshift credentials
├── iam.tf               # IAM roles and policies (EMR, Redshift)
├── emr.tf               # EMR Serverless application
├── vpc.tf               # VPC, subnets, security groups (required for EMR Serverless)
├── redshift.tf          # Redshift Serverless namespace, workgroup, bootstrap SQL
├── athena.tf            # Athena workgroup and Glue table
├── glue.tf              # Glue Data Catalog database
├── cloudwatch.tf        # CloudWatch log groups
├── kms.tf               # KMS keys (optional)
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── locals.tf            # Local values
├── versions.tf          # Provider versions
├── test.sh              # Automated testing script
├── QUERY_EXAMPLES.md    # Complete examples for querying curated data
├── spark_job/
│   ├── etl_job.py       # PySpark ETL script
│   └── requirements.txt # Python dependencies
├── redshift/
│   └── bootstrap.sql    # Dim table creation
└── data/
    └── raw/             # Sample JSON files
```

## Security Features

- **Least Privilege IAM**: Separate read/write policies with Statement IDs
- **S3 Encryption**: AES256 (default) or KMS (optional)
- **Secrets Manager**: Redshift credentials stored securely
- **Public Access Block**: S3 buckets block public access
- **Force Destroy**: S3 bucket, Athena workgroup, and KMS keys can be force-deleted for cleanup

## ETL Job Details

The Spark job (`spark_job/etl_job.py`):

1. Reads JSON from S3 `raw/` prefix
2. Connects to Redshift via **Redshift Data API** (pure Python via boto3, no Java/JDBC needed)
3. Loads `dim_category` table into Spark DataFrame
4. Performs broadcast join on `category_id`
5. Aggregates by date and category (sum amounts, count transactions)
6. Writes partitioned Parquet to S3 `curated/` prefix

### Why Redshift Data API instead of JDBC?

- **Pure Python**: No Java/JDBC driver required - uses boto3 already in EMR Serverless
- **Serverless-friendly**: Works seamlessly with Redshift Serverless workgroups
- **Simpler setup**: No JAR file management or dependency resolution
- **Most common modern approach**: Recommended by AWS for PySpark + Redshift Serverless

**Alternative (JDBC)**: Faster for very large datasets but requires Java driver JAR management.

## Logging and Monitoring

### CloudWatch Log Groups

All services send logs to CloudWatch with 1-day retention:

- **EMR Serverless**: `/aws/emr-serverless/{prefix}-spark-app`
  - Driver and executor logs
  - Also available in S3: `s3://{bucket}/logs/`

- **Redshift Serverless**: `/aws/redshift-serverless/{prefix}-namespace`
  - Connection logs and user activity logs

- **Athena**: `/aws/athena/{prefix}-curated-workgroup`
  - Query execution logs (automatic)

View logs:

```bash
# Get region from Terraform
REGION=$(terraform output -raw aws_region)

# EMR logs
aws logs tail $(terraform output -json | jq -r '.cloudwatch_log_groups.value.emr_serverless') \
  --follow \
  --region $REGION

# Redshift logs
aws logs tail $(terraform output -json | jq -r '.cloudwatch_log_groups.value.redshift_connectionlog') \
  --follow \
  --region $REGION
```

## Troubleshooting

### Redshift Connection Issues

- Verify IAM role has:
  - `redshift-data:ExecuteStatement`
  - `redshift-data:DescribeStatement`
  - `redshift-data:GetStatementResult`
  - `redshift-serverless:GetCredentials`
  - `redshift-serverless:GetWorkgroup`
- Verify VPC is configured for EMR Serverless (required for outbound internet access)
- Check CloudWatch logs for Data API errors
- Verify Redshift workgroup is active: `aws redshift-serverless get-workgroup --workgroup-name <name>`

### EMR Job Fails

- Check CloudWatch logs: `/aws/emr-serverless/{prefix}-spark-app`
- Check S3 logs: `aws s3 ls s3://$(terraform output -raw s3_bucket_name)/logs/ --recursive`
- Verify Spark script path in S3
- Check IAM role permissions for:
  - S3 read/write
  - Redshift Data API (`redshift-data:*`)
  - Redshift Serverless (`redshift-serverless:GetCredentials`)
- Verify VPC configuration (required for outbound internet access)
- Check that EMR application is in `STOPPED` or `CREATED` state before updating network config

### Sample Data Not Found

- Run `terraform apply -target=aws_s3_object.sample_data` to upload sample JSON files
- Verify files exist in `data/raw/` directory

### No Logs in CloudWatch

- Verify log groups exist: `terraform output cloudwatch_log_groups`
- Check IAM permissions allow CloudWatch Logs write access
- Ensure EMR job has `cloudWatchLoggingConfiguration` enabled

## Teardown

Destroy all infrastructure:

```bash
terraform destroy
```

This will:

- Delete all AWS resources
- Delete S3 bucket and all contents (force_destroy enabled)
- Delete KMS keys (7-day deletion window)
- Clean up IAM roles and policies

**Notes**:

- **KMS keys**: Have a 7-day deletion window. To force immediate deletion (not recommended for production):

  ```bash
  aws kms schedule-key-deletion --key-id <key-id> --pending-window-in-days 7
  ```

- **Athena workgroup**: Configured with `force_destroy = true` to allow deletion even with query history.

## Cost Considerations

- **Redshift Serverless**: Charges based on RPU-hours (minimum 32 RPU)
- **EMR Serverless**: Charges for vCPU-hours and GB-hours of compute
- **S3**: Storage and request costs
- **Secrets Manager**: $0.40/month per secret

For demo purposes, keep workloads small and destroy resources when not in use.

## Next Steps

- Query curated data - see [QUERY_EXAMPLES.md](QUERY_EXAMPLES.md) for:
  - Athena SQL queries
  - Local analysis with pandas
  - BI tool integration (QuickSight, Tableau)
  - Loading into other data warehouses
- Enable KMS encryption for production
- Add more complex ETL transformations
- Set up scheduled EMR jobs via EventBridge
- Add monitoring and alerting (CloudWatch alarms)
- Scale up Redshift Serverless for larger datasets
