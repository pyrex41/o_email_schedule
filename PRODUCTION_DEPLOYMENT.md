# Production Deployment Guide

This guide covers the production deployment of the OCaml Email Scheduler on Fly.io with Google Cloud Storage (GCS) integration.

## Architecture Overview

The system uses a **sqlite3_rsync + GCS** architecture for robust, production-ready database synchronization:

1. **OCaml Application**: Core business logic with native SQLite bindings
2. **Fly.io**: Container orchestration and execution platform
3. **Google Cloud Storage**: Persistent database storage with versioning
4. **sqlite3_rsync**: High-performance database synchronization

## Prerequisites

### 1. Google Cloud Setup

1. Create a GCS bucket for database storage:
   ```bash
   gsutil mb gs://your-email-scheduler-bucket
   ```

2. **CRITICAL**: Enable Object Versioning on the bucket for backup protection:
   ```bash
   gsutil versioning set on gs://your-email-scheduler-bucket
   ```

3. Create a service account with Storage Admin permissions:
   ```bash
   gcloud iam service-accounts create email-scheduler-sa
   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
     --member="serviceAccount:email-scheduler-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
     --role="roles/storage.admin"
   ```

4. Generate and download the service account key:
   ```bash
   gcloud iam service-accounts keys create keyfile.json \
     --iam-account=email-scheduler-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com
   ```

### 2. Fly.io Setup

1. Install flyctl:
   ```bash
   curl -L https://fly.io/install.sh | sh
   ```

2. Authenticate:
   ```bash
   flyctl auth login
   ```

## Deployment Process

### 1. Set Secrets

Set the GCS keyfile as a secret (replace with actual keyfile content):
```bash
flyctl secrets set GCS_KEYFILE_JSON="$(cat keyfile.json)"
```

### 2. Update Configuration

Edit `fly.toml` and update:
```toml
[env]
  GCS_BUCKET_NAME = "your-email-scheduler-bucket"
  ORG_ID = "99"  # Your organization ID
```

### 3. Deploy

For first deployment:
```bash
flyctl launch
```

For subsequent deployments:
```bash
flyctl deploy
```

### 4. Verify Deployment

Check logs to ensure successful startup:
```bash
flyctl logs
```

Expected log sequence:
```
🚀 Starting Email Scheduler with GCS Sync...
🔐 Setting up GCS authentication...
📁 Mounting GCS bucket: your-bucket...
✅ GCS bucket mounted successfully
📥 Syncing database from GCS to local working copy...
✅ Database synced from GCS successfully
🏃 Running OCaml Email Scheduler...
✅ OCaml scheduler completed successfully
📤 Syncing modified database back to GCS...
✅ Database synced back to GCS successfully
🎉 Email Scheduler completed successfully!
```

## Backup and Recovery Strategy

### Primary Backup: GCS Object Versioning

**Object Versioning is your primary safety net.** When enabled on your GCS bucket, every change to the database creates a new version while preserving the previous versions.

#### Recovery Procedure

If the database becomes corrupted or you need to restore a previous state:

1. **Via Google Cloud Console** (Recommended):
   - Navigate to Cloud Storage → Your Bucket
   - Find the `org-data/99.db` object
   - Click on the object name
   - Go to the "Version history" tab
   - Select the version you want to restore
   - Click "Restore" to make it the current version

2. **Via Command Line**:
   ```bash
   # List all versions
   gsutil ls -a gs://your-bucket/org-data/99.db
   
   # Restore a specific version (replace GENERATION with actual number)
   gsutil cp gs://your-bucket/org-data/99.db#GENERATION gs://your-bucket/org-data/99.db
   ```

### Secondary Backup: Manual Snapshots

For critical operations, create manual backups:
```bash
# Download current database
gsutil cp gs://your-bucket/org-data/99.db ./backup-$(date +%Y%m%d-%H%M%S).db

# Upload a backup
gsutil cp ./backup.db gs://your-bucket/backups/manual-backup-$(date +%Y%m%d-%H%M%S).db
```

## Monitoring and Logging

### Viewing Logs

Real-time logs:
```bash
flyctl logs -f
```

Historical logs:
```bash
flyctl logs --since 1h
```

### Key Metrics to Monitor

1. **Scheduler Completion**: Look for "🎉 Email Scheduler completed successfully!"
2. **Sync Success**: Verify both download and upload sync operations
3. **Error Patterns**: Watch for "❌ ERROR:" messages
4. **Performance**: Monitor execution time and contact processing rates

### Alerting

Set up monitoring for:
- Failed scheduler runs
- GCS sync failures
- Container restart loops
- High memory usage

## Troubleshooting

### Common Issues

#### 1. GCS Authentication Failure
```
❌ ERROR: GCS_KEYFILE_JSON environment variable is not set
```
**Solution**: Ensure the secret is set correctly:
```bash
flyctl secrets set GCS_KEYFILE_JSON="$(cat keyfile.json)"
```

#### 2. Mount Failure
```
❌ ERROR: Failed to mount GCS bucket
```
**Solutions**:
- Verify bucket name in `fly.toml`
- Check service account permissions
- Ensure gcsfuse is working in container

#### 3. Database Sync Failure
```
❌ ERROR: Failed to sync database from GCS
```
**Solutions**:
- Check if database file exists on GCS
- Verify sqlite3_rsync is working
- Check disk space on persistent volume

#### 4. OCaml Scheduler Failure
```
❌ ERROR: OCaml scheduler failed
```
**Solutions**:
- Review OCaml-specific error messages
- Check database schema compatibility
- Verify contact data integrity

### Emergency Recovery

If the system is completely broken:

1. **Restore Database from Backup**:
   - Use GCS versioning to restore known-good database
   - Verify database integrity

2. **Restart Application**:
   ```bash
   flyctl restart
   ```

3. **Scale Down/Up** (if persistent issues):
   ```bash
   flyctl scale count 0
   flyctl scale count 1
   ```

## Performance Optimization

### Resource Tuning

Monitor resource usage and adjust `fly.toml`:
```toml
[[vm]]
  memory = "8gb"    # Increase if needed
  cpu_kind = "performance"
  cpus = 8          # Scale with contact volume
```

### Database Optimization

The OCaml scheduler includes automatic SQLite optimization:
- WAL mode for concurrent access
- Large cache sizes for bulk operations
- Optimized indexes for query performance

## Security Best Practices

1. **Secrets Management**:
   - Never commit GCS keyfiles to version control
   - Rotate service account keys regularly
   - Use Fly.io secrets for sensitive data

2. **Access Control**:
   - Limit GCS bucket access to scheduler service account only
   - Use least-privilege IAM roles
   - Monitor GCS access logs

3. **Network Security**:
   - Use private networking where possible
   - Enable GCS bucket encryption

## Maintenance

### Regular Tasks

1. **Monthly**: Review GCS storage costs and clean up old versions if needed
2. **Quarterly**: Rotate service account keys
3. **As Needed**: Update base Docker images for security patches

### Updates

To deploy updates:
```bash
git pull origin main
flyctl deploy
```

Always test updates in a staging environment first.

## Support

For issues with:
- **OCaml Application**: Check application logs and contact data
- **Fly.io Platform**: Use `flyctl doctor` and Fly.io support
- **GCS Integration**: Verify authentication and bucket permissions
- **Database Issues**: Check SQLite file integrity and sync logs