# Tigris Deployment Guide

This guide covers the production deployment of the OCaml Email Scheduler on Fly.io with Tigris object storage integration.

## Architecture Overview

The system uses a **sqlite3_rsync + Tigris** architecture for robust, production-ready database synchronization:

1. **TigrisFS Mount**: The Fly.io container mounts your Tigris bucket as a filesystem using the optimized TigrisFS FUSE driver
2. **Database Sync**: `sqlite3_rsync` efficiently synchronizes the SQLite database between local storage and Tigris
3. **Atomic Operations**: All database operations are atomic, ensuring data consistency
4. **Zero Egress Costs**: Tigris provides free egress, making multi-environment access cost-effective

## Prerequisites

1. **Fly.io Account**: [Sign up at fly.io](https://fly.io/app/sign-up)
2. **Tigris Account**: [Sign up at tigris.dev](https://www.tigris.dev/)
3. **flyctl CLI**: [Install flyctl](https://fly.io/docs/hands-on/install-flyctl/)

## Setup Instructions

### 1. Create Tigris Storage on Fly.io

Fly.io provides native Tigris integration. Create your storage bucket:

```bash
# Create a new Tigris bucket (this is the preferred method on Fly.io)
fly storage create --name your-email-scheduler-bucket

# Or create through the Tigris console if you prefer manual setup
```

The `fly storage create` command automatically:
- Creates the bucket in Tigris
- Sets up optimized routing from Fly.io infrastructure
- Provides the necessary credentials as environment variables

### 2. Configure Secrets

Set your Tigris credentials as Fly.io secrets:

```bash
# If using fly storage create, these are set automatically
# Otherwise, set them manually with your Tigris credentials
flyctl secrets set AWS_ACCESS_KEY_ID="tid_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
flyctl secrets set AWS_SECRET_ACCESS_KEY="tsec_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### 3. Update fly.toml Configuration

Update your `fly.toml` with the correct bucket name:

```toml
[env]
  BUCKET_NAME = "your-email-scheduler-bucket"  # Use your actual bucket name
  ORG_ID = "99"
  OCAMLLOG = "info"
  AWS_REGION = "auto"
  AWS_ENDPOINT_URL_S3 = "https://fly.storage.tigris.dev"
```

### 4. Deploy to Fly.io

```bash
# Deploy the application
flyctl deploy

# Create a persistent volume for local database copy
flyctl volumes create scheduler_data --region ord --size 10

# Run the scheduler
flyctl machine run . --region ord
```

## Expected Output

When the scheduler runs successfully, you'll see output like:

```
🚀 Starting Email Scheduler with Tigris Sync...
🔐 Setting up Tigris authentication...
Using endpoint: https://fly.storage.tigris.dev
Bucket: your-email-scheduler-bucket
📁 Mounting Tigris bucket: your-email-scheduler-bucket...
✅ Tigris bucket mounted successfully
📥 Syncing database from Tigris to local working copy...
✅ Database synced from Tigris successfully
🏃 Running OCaml Email Scheduler...
✅ OCaml scheduler completed successfully
📤 Syncing modified database back to Tigris...
✅ Database synced back to Tigris successfully
🎉 Email Scheduler completed successfully!
```

## Backup and Recovery

### Primary Backup: Tigris Global Distribution

**Tigris automatically replicates your data globally** across multiple regions, providing built-in redundancy and disaster recovery.

Key advantages:
- **Automatic multi-region replication**: Your SQLite database is automatically replicated across Tigris's global network
- **Strong consistency**: All replicas are strongly consistent, ensuring data integrity
- **Zero egress fees**: You can restore your database from any region without additional costs
- **High availability**: Built on FoundationDB for enterprise-grade reliability

### Manual Backup Strategy

For additional protection, you can implement periodic backups:

```bash
# Manual backup script (run via cron or Fly.io scheduled machine)
#!/bin/bash
BACKUP_NAME="backup-$(date +%Y%m%d-%H%M%S).db"
sqlite3 /app/data/working_copy.db ".backup /tmp/$BACKUP_NAME"

# Upload to a separate backup directory in Tigris
aws s3 cp "/tmp/$BACKUP_NAME" "s3://$BUCKET_NAME/backups/$BACKUP_NAME" \
  --endpoint-url "$AWS_ENDPOINT_URL_S3"
```

## Monitoring and Troubleshooting

### Health Checks

Monitor your deployment with Fly.io logs:

```bash
# View real-time logs
flyctl logs

# Check machine status
flyctl status

# Access Tigris bucket contents
flyctl ssh console
ls -la /tigris/org-data/
```

### Common Issues and Solutions

#### 1. Tigris Authentication Failure

```
❌ ERROR: AWS_ACCESS_KEY_ID environment variable is not set
```

**Solution:**
```bash
flyctl secrets set AWS_ACCESS_KEY_ID="your-tigris-access-key"
flyctl secrets set AWS_SECRET_ACCESS_KEY="your-tigris-secret-key"
```

#### 2. TigrisFS Mount Failure

```
❌ ERROR: Failed to mount Tigris bucket
```

**Solutions:**
- Verify bucket name is correct in `fly.toml`
- Ensure FUSE is enabled in container (already configured in Dockerfile)
- Check Tigris credentials are valid
- Verify network connectivity to Tigris endpoint

#### 3. Database Sync Failure

```
❌ ERROR: Failed to sync database from Tigris
```

**Solutions:**
- Check if database file exists in Tigris bucket
- Verify sqlite3_rsync binary is installed and executable
- Ensure sufficient disk space in `/app/data` volume
- Check file permissions in mounted Tigris filesystem

## Performance Optimization

### TigrisFS Performance

The TigrisFS FUSE driver is optimized for small objects and provides:
- **5-10x better performance** than generic S3 FUSE solutions
- **Sub-millisecond latency** for small file operations
- **Automatic caching** for frequently accessed files

### Resource Allocation

For optimal performance, ensure your `fly.toml` allocates sufficient resources:

```toml
[[vm]]
  memory = "4gb"     # Sufficient for database operations and caching
  cpu_kind = "performance"
  cpus = 4           # Multiple cores for concurrent I/O operations
```

## Cost Optimization

### Tigris Pricing Benefits

- **Zero egress fees**: No charges for data transfer out of Tigris
- **Global distribution included**: No additional costs for multi-region replication
- **Pay for what you use**: Only pay for actual storage consumed

### Storage Lifecycle

Tigris automatically optimizes storage costs:
- **Frequent access**: Data is cached globally for fast access
- **Infrequent access**: Data is automatically moved to more cost-effective storage tiers
- **No complex lifecycle rules needed**: Everything is handled automatically

## Security Best Practices

1. **Credential Management**:
   - Never commit Tigris credentials to version control
   - Use Fly.io secrets for credential storage
   - Rotate credentials periodically

2. **Bucket Security**:
   - Limit Tigris bucket access to scheduler service account only
   - Enable bucket-level encryption (enabled by default in Tigris)
   - Monitor access logs through Tigris console

3. **Network Security**:
   - Use Fly.io's private networking where possible
   - Enable TLS for all Tigris communications (default with TigrisFS)

## Maintenance Tasks

- **Weekly**: Review application logs for any sync errors or performance issues
- **Monthly**: Review Tigris storage usage and costs in the Tigris console
- **Quarterly**: Verify backup restoration procedures work correctly

## Support and Monitoring

- **Application Logs**: Monitor via `flyctl logs`
- **Tigris Console**: Monitor storage usage and performance at [console.tigris.dev](https://console.tigris.dev)
- **Fly.io Dashboard**: Monitor infrastructure and resource usage
- **Error Handling**: The scheduler automatically retries failed operations and logs detailed error information