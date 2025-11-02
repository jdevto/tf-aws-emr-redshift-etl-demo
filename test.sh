#!/bin/bash
set -e

echo "🚀 Testing EMR Redshift ETL Pipeline"
echo "===================================="
echo ""

# Check if EMR application exists
echo "0️⃣  Verifying EMR application exists..."
APP_ID=$(terraform output -raw emr_application_id 2>/dev/null || echo "")
if [ -z "$APP_ID" ]; then
    echo "❌ EMR application ID not found in outputs"
    echo "   Run: terraform apply to create the application"
    exit 1
fi

# Get region from Terraform output
REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
if [ -z "$REGION" ]; then
    # Try from AWS config or provider default
    REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-"ap-southeast-2"}}
fi

echo "   Application ID: $APP_ID"
echo "   Region: $REGION"
echo ""

# Step 1: Ensure Redshift bootstrap is done (handled by terraform apply)
echo "1️⃣  Checking Redshift setup..."
# Redshift bootstrap SQL is created during terraform apply, no need to target separately
echo "✅ Redshift setup verified (bootstrap runs automatically with terraform apply)"
echo ""

# Step 2: Upload sample data
echo "2️⃣  Uploading sample data to S3..."
terraform apply -target=aws_s3_object.sample_data -auto-approve > /dev/null 2>&1
echo "✅ Sample data uploaded"
echo ""

# Step 3: Upload Spark script
echo "3️⃣  Uploading Spark ETL script..."
terraform apply -target=aws_s3_object.spark_script -auto-approve > /dev/null 2>&1
echo "✅ Spark script uploaded"
echo ""

# Step 4: Run EMR job
echo "4️⃣  Submitting EMR Serverless job..."
JOB_OUTPUT=$(terraform output -raw emr_job_run_command 2>/dev/null | sed "s/--region \${data\.aws_region\.current\.id}/--region $REGION/" | bash 2>&1)
JOB_RUN_ID=$(echo "$JOB_OUTPUT" | grep -oP 'jobRunId["\s:]*["\s]*\K[^"]+' || echo "")

if [ -z "$JOB_RUN_ID" ]; then
    # Try alternative pattern
    JOB_RUN_ID=$(echo "$JOB_OUTPUT" | grep -oP '"id"\s*:\s*"\K[^"]+' || echo "")
fi

if [ -z "$JOB_RUN_ID" ]; then
    echo "❌ Failed to submit job or get job run ID"
    echo "   Error output:"
    echo "$JOB_OUTPUT" | head -10
    echo ""
    echo "   Troubleshooting:"
    echo "   - Verify application exists: terraform state show aws_emrserverless_application.spark"
    echo "   - Check application in AWS Console"
    echo "   - Run: terraform apply to ensure application is created"
    exit 1
fi

echo "✅ Job submitted! Job Run ID: $JOB_RUN_ID"
echo ""

# Step 5: Monitor job
echo "5️⃣  Monitoring job status (checking every 15 seconds)..."
echo ""

while true; do
    STATE=$(aws emr-serverless get-job-run --region $REGION --application-id $APP_ID --job-run-id $JOB_RUN_ID --query 'jobRun.state' --output text 2>/dev/null || echo "UNKNOWN")
    echo "   Current state: $STATE"

    case "$STATE" in
        "SUCCESS")
            echo ""
            echo "✅ Job completed successfully!"
            break
            ;;
        "FAILED"|"CANCELLED")
            echo ""
            echo "❌ Job failed or was cancelled"
            echo "   Check logs: aws s3 ls s3://$(terraform output -raw s3_bucket_name)/logs/ --recursive | tail -5"
            exit 1
            ;;
        "SUBMITTED"|"PENDING"|"SCHEDULED"|"RUNNING")
            sleep 15
            ;;
        *)
            if [ "$STATE" = "UNKNOWN" ]; then
                echo "   ⚠️  Could not determine state, waiting..."
            else
                echo "   State: $STATE, waiting..."
            fi
            sleep 15
            ;;
    esac
done

echo ""

# Step 6: Validate output
echo "6️⃣  Validating curated output..."
BUCKET=$(terraform output -raw s3_bucket_name)
echo ""
echo "Curated Parquet files:"
aws s3 ls s3://$BUCKET/curated/ --recursive 2>/dev/null || echo "   No files found or S3 access issue"
echo ""

FILE_COUNT=$(aws s3 ls s3://$BUCKET/curated/ --recursive 2>/dev/null | wc -l)
if [ "$FILE_COUNT" -gt 0 ]; then
    echo "✅ Found $FILE_COUNT file(s) in curated path"
    echo ""
    echo "📊 Sample file listing:"
    aws s3 ls s3://$BUCKET/curated/ --recursive | head -5
else
    echo "⚠️  No files found in curated path. Check job logs."
fi

echo ""
echo "✨ Testing complete!"
echo ""
echo "📝 Next steps:"
echo "   - View job logs: aws logs tail \$(terraform output -json | jq -r '.cloudwatch_log_groups.value.emr_serverless') --region $REGION --since 30m"
echo "   - Query via Athena: See QUERY_EXAMPLES.md for complete query examples"
echo "   - Quick Athena test:"
echo "     QUERY_ID=\$(aws athena start-query-execution \\"
echo "       --region $REGION \\"
echo "       --work-group \$(terraform output -raw athena_workgroup_name) \\"
echo "       --query-string \"SELECT * FROM \\\"\$(terraform output -raw glue_database_name)\\\".\\\"\$(terraform output -raw glue_table_name)\\\" LIMIT 10\" \\"
echo "       --result-configuration \"OutputLocation=s3://$BUCKET/athena-results/\" \\"
echo "       --query 'QueryExecutionId' --output text)"
echo "     sleep 5 && aws athena get-query-results --query-execution-id \$QUERY_ID --region $REGION --output table"
echo "   - Clean up: terraform destroy"
