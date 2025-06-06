use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use libsql::Builder;
use log::{info, warn, error, debug};
use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::Duration;

#[derive(Parser)]
#[command(name = "turso-sync")]
#[command(about = "A CLI tool for syncing SQLite databases with Turso")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Sync from Turso to local replica
    Sync {
        /// Path to local replica database
        #[arg(short, long, default_value = "local_replica.db")]
        replica_path: String,
        
        /// Turso database URL
        #[arg(short, long)]
        url: Option<String>,
        
        /// Turso auth token
        #[arg(short, long)]
        token: Option<String>,
    },
    
    /// Copy replica to working copy
    Copy {
        /// Path to source database
        #[arg(short, long, default_value = "local_replica.db")]
        source: String,
        
        /// Path to destination database
        #[arg(short, long, default_value = "working_copy.db")]
        dest: String,
    },
    
    /// Generate diff and apply to Turso
    Push {
        /// Path to local replica database
        #[arg(short, long, default_value = "local_replica.db")]
        replica_path: String,
        
        /// Path to working copy database
        #[arg(short, long, default_value = "working_copy.db")]
        working_path: String,
        
        /// Turso database URL
        #[arg(long)]
        url: Option<String>,
        
        /// Turso auth token
        #[arg(long)]
        token: Option<String>,
        
        /// Path to store the diff SQL file
        #[arg(long, default_value = "diff.sql")]
        diff_file: String,
    },
    
    /// Apply diff file to synced database and sync to remote (uses offline sync)
    ApplyDiff {
        /// Path to local synced database
        #[arg(short, long, default_value = "local_replica.db")]
        db_path: String,
        
        /// Path to diff SQL file to apply
        #[arg(short, long, default_value = "diff.sql")]
        diff_file: String,
        
        /// Turso database URL for sync
        #[arg(short, long)]
        sync_url: Option<String>,
        
        /// Turso auth token
        #[arg(short, long)]
        token: Option<String>,
        
        /// Skip sync after applying diff
        #[arg(long)]
        no_sync: bool,
    },
    
    /// Initialize and sync a database using offline sync capabilities
    OfflineSync {
        /// Path to local database
        #[arg(short, long, default_value = "working_copy.db")]
        db_path: String,
        
        /// Turso database URL for sync
        #[arg(short, long)]
        sync_url: Option<String>,
        
        /// Turso auth token
        #[arg(short, long)]
        token: Option<String>,
        
        /// Direction: 'pull' from remote, 'push' to remote, or 'both' (default)
        #[arg(long, default_value = "both")]
        direction: String,
    },
    
    /// Full workflow: sync -> copy -> wait for changes -> push
    Workflow {
        /// Path to local replica database
        #[arg(short, long, default_value = "local_replica.db")]
        replica_path: String,
        
        /// Path to working copy database
        #[arg(short, long, default_value = "working_copy.db")]
        working_path: String,
        
        /// Turso database URL
        #[arg(long)]
        url: Option<String>,
        
        /// Turso auth token
        #[arg(long)]
        token: Option<String>,
        
        /// Sync interval in seconds
        #[arg(long, default_value = "300")]
        sync_interval: u64,
    },

    /// Bidirectional sync with Turso using libSQL sync (pulls and pushes changes)
    LibsqlSync {
        /// Path to local synced database
        #[arg(short, long, default_value = "working_copy.db")]
        db_path: String,

        /// Turso database URL for sync
        #[arg(short, long)]
        sync_url: Option<String>,

        /// Turso auth token
        #[arg(short, long)]
        token: Option<String>,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    // Load .env file if it exists (ignore errors if file doesn't exist)
    let _ = dotenv::dotenv();
    
    env_logger::init();
    let cli = Cli::parse();

    match cli.command {
        Commands::Sync { replica_path, url, token } => {
            let url = get_env_or_arg(url, "TURSO_DATABASE_URL")?;
            let token = get_env_or_arg(token, "TURSO_AUTH_TOKEN")?;
            sync_from_turso(&replica_path, &url, &token).await?;
        }
        Commands::Copy { source, dest } => {
            copy_database(&source, &dest)?;
        }
        Commands::Push { replica_path, working_path, url, token, diff_file } => {
            let url = get_env_or_arg(url, "TURSO_DATABASE_URL")?;
            let token = get_env_or_arg(token, "TURSO_AUTH_TOKEN")?;
            push_to_turso(&replica_path, &working_path, &url, &token, &diff_file).await?;
        }
        Commands::ApplyDiff { db_path, diff_file, sync_url, token, no_sync } => {
            let url = get_env_or_arg(sync_url, "TURSO_DATABASE_URL")?;
            let token = get_env_or_arg(token, "TURSO_AUTH_TOKEN")?;
            apply_diff_to_turso(&db_path, &diff_file, &url, &token, no_sync).await?;
        }
        Commands::OfflineSync { db_path, sync_url, token, direction } => {
            let url = get_env_or_arg(sync_url, "TURSO_DATABASE_URL")?;
            let token = get_env_or_arg(token, "TURSO_AUTH_TOKEN")?;
            offline_sync(&db_path, &url, &token, &direction).await?;
        }
        Commands::Workflow { replica_path, working_path, url, token, sync_interval } => {
            let url = get_env_or_arg(url, "TURSO_DATABASE_URL")?;
            let token = get_env_or_arg(token, "TURSO_AUTH_TOKEN")?;
            run_workflow(&replica_path, &working_path, &url, &token, sync_interval).await?;
        }
        Commands::LibsqlSync { db_path, sync_url, token } => {
            let url = get_env_or_arg(sync_url, "TURSO_DATABASE_URL")?;
            let token = get_env_or_arg(token, "TURSO_AUTH_TOKEN")?;
            libsql_sync(&db_path, &url, &token).await?;
        }
    }

    Ok(())
}

/// Helper function to get value from argument or environment variable
fn get_env_or_arg(arg: Option<String>, env_var: &str) -> Result<String> {
    if let Some(value) = arg {
        Ok(value)
    } else if let Ok(value) = env::var(env_var) {
        Ok(value)
    } else {
        Err(anyhow::anyhow!(
            "{} not provided as argument or environment variable. Set {} or use --{} flag",
            env_var,
            env_var,
            env_var.to_lowercase().replace('_', "-")
        ))
    }
}

/// Helper function to make CREATE statements idempotent
fn make_create_statement_idempotent(statement: &str) -> String {
    let trimmed = statement.trim();
    if trimmed.starts_with("CREATE INDEX") && !trimmed.contains("IF NOT EXISTS") {
        trimmed.replace("CREATE INDEX", "CREATE INDEX IF NOT EXISTS")
    } else if trimmed.starts_with("CREATE TABLE") && !trimmed.contains("IF NOT EXISTS") {
        trimmed.replace("CREATE TABLE", "CREATE TABLE IF NOT EXISTS")
    } else if trimmed.starts_with("CREATE UNIQUE INDEX") && !trimmed.contains("IF NOT EXISTS") {
        trimmed.replace("CREATE UNIQUE INDEX", "CREATE UNIQUE INDEX IF NOT EXISTS")
    } else if trimmed.starts_with("CREATE VIEW") && !trimmed.contains("IF NOT EXISTS") {
        trimmed.replace("CREATE VIEW", "CREATE VIEW IF NOT EXISTS")
    } else if trimmed.starts_with("CREATE TRIGGER") && !trimmed.contains("IF NOT EXISTS") {
        trimmed.replace("CREATE TRIGGER", "CREATE TRIGGER IF NOT EXISTS")
    } else {
        statement.to_string()
    }
}

/// Sync from Turso to local replica using embedded replica
async fn sync_from_turso(replica_path: &str, url: &str, token: &str) -> Result<()> {
    info!("Syncing from Turso to local replica: {}", replica_path);
    
    let db = Builder::new_remote_replica(replica_path, url.to_string(), token.to_string())
        .build()
        .await
        .context("Failed to create remote replica")?;
    
    // Perform initial sync
    db.sync().await.context("Failed to sync database")?;
    
    info!("Successfully synced from Turso to {}", replica_path);
    Ok(())
}

/// Copy database file
fn copy_database(source: &str, dest: &str) -> Result<()> {
    info!("Copying database from {} to {}", source, dest);
    
    if !Path::new(source).exists() {
        return Err(anyhow::anyhow!("Source database {} does not exist", source));
    }
    
    fs::copy(source, dest)
        .context("Failed to copy database file")?;
    
    info!("Successfully copied database to {}", dest);
    Ok(())
}

/// Generate diff using sqldiff and apply to Turso
async fn push_to_turso(
    replica_path: &str,
    working_path: &str,
    url: &str,
    token: &str,
    diff_file: &str,
) -> Result<()> {
    info!("Generating diff and pushing to Turso");
    
    // Check if both databases exist
    if !Path::new(replica_path).exists() {
        return Err(anyhow::anyhow!("Local replica {} does not exist", replica_path));
    }
    
    if !Path::new(working_path).exists() {
        return Err(anyhow::anyhow!("Working copy {} does not exist", working_path));
    }
    
    // Generate diff using sqldiff
    info!("Generating diff using sqldiff");
    let output = Command::new("sqldiff")
        .arg("--transaction")
        .arg(replica_path)
        .arg(working_path)
        .output()
        .context("Failed to run sqldiff - make sure it's installed and in PATH")?;
    
    if !output.status.success() {
        error!("sqldiff failed: {}", String::from_utf8_lossy(&output.stderr));
        return Err(anyhow::anyhow!("sqldiff command failed"));
    }
    
    let diff_sql = String::from_utf8(output.stdout)
        .context("Failed to parse sqldiff output as UTF-8")?;
    
    if diff_sql.trim().is_empty() {
        info!("No changes detected - databases are identical");
        return Ok(());
    }
    
    // Save diff to file for debugging
    fs::write(diff_file, &diff_sql)
        .context("Failed to write diff file")?;
    
    info!("Generated diff SQL ({} bytes), saved to {}", diff_sql.len(), diff_file);
    debug!("Diff SQL:\n{}", diff_sql);
    
    // Apply diff to Turso with batching for large diffs
    info!("Applying changes to Turso");
    let db = Builder::new_remote(url.to_string(), token.to_string())
        .build()
        .await
        .context("Failed to connect to Turso")?;
    
    let conn = db.connect().context("Failed to get connection")?;
    
    // Check if we need to batch the operations
    let statements: Vec<&str> = diff_sql.split(';').collect();
    let non_empty_statements: Vec<&str> = statements
        .iter()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty() && *s != "BEGIN TRANSACTION" && *s != "COMMIT")
        .collect();
    
    if non_empty_statements.len() > 1000 {
        info!("Large diff detected ({} statements), processing in batches", non_empty_statements.len());
        
        // Process CREATE statements first (indexes, tables, etc.)
        let create_statements: Vec<&str> = non_empty_statements
            .iter()
            .filter(|s| s.starts_with("CREATE"))
            .copied()
            .collect();
        
        if !create_statements.is_empty() {
            info!("Applying {} CREATE statements", create_statements.len());
            
            // Modify CREATE statements to be idempotent
            let safe_create_statements: Vec<String> = create_statements
                .iter()
                .map(|s| make_create_statement_idempotent(s))
                .collect();
            
            let create_batch = safe_create_statements.join(";\n") + ";";
            conn.execute_batch(&create_batch)
                .await
                .context("Failed to execute CREATE statements")?;
        }
        
        // Process INSERT/UPDATE/DELETE statements in batches
        let data_statements: Vec<&str> = non_empty_statements
            .iter()
            .filter(|s| !s.starts_with("CREATE"))
            .copied()
            .collect();
        
        if !data_statements.is_empty() {
            let batch_size = 500; // Adjust batch size as needed
            let total_batches = (data_statements.len() + batch_size - 1) / batch_size;
            
            info!("Processing {} data statements in {} batches of {}", 
                  data_statements.len(), total_batches, batch_size);
            
            for (batch_num, batch) in data_statements.chunks(batch_size).enumerate() {
                info!("Processing batch {}/{} ({} statements)", 
                      batch_num + 1, total_batches, batch.len());
                
                let batch_sql = batch.join(";\n") + ";";
                conn.execute_batch(&batch_sql)
                    .await
                    .with_context(|| format!("Failed to execute batch {}/{}", batch_num + 1, total_batches))?;
                
                // Small delay between batches to avoid overwhelming the server
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
        }
    } else {
        // Small diff, execute as single batch
        conn.execute_batch(&diff_sql)
            .await
            .context("Failed to execute diff SQL on Turso")?;
    }
    
    info!("Successfully applied changes to Turso");
    
    // Update local replica to match
    sync_from_turso(replica_path, url, token).await?;
    
    Ok(())
}

/// Apply diff file to local replica database and sync to remote (uses offline sync)
/// The diff should contain changes to transform the replica into the working copy state
async fn apply_diff_to_turso(
    db_path: &str,
    diff_file: &str,
    url: &str,
    token: &str,
    no_sync: bool,
) -> Result<()> {
    info!("Applying diff file to local replica database and syncing to Turso");
    
    // Check if the database exists
    if !Path::new(db_path).exists() {
        return Err(anyhow::anyhow!("Local database {} does not exist", db_path));
    }
    
    // Check if diff file exists
    if !Path::new(diff_file).exists() {
        return Err(anyhow::anyhow!("Diff file {} does not exist", diff_file));
    }
    
    // Read diff file
    let diff_sql = fs::read_to_string(diff_file)
        .context("Failed to read diff file")?;
    
    if diff_sql.trim().is_empty() {
        info!("No changes detected - diff file is empty");
        return Ok(());
    }
    
    info!("Read diff file: {} bytes", diff_sql.len());
    debug!("Diff SQL:\n{}", diff_sql);
    
    // For diff application, we'll use a simple local connection and only sync if requested
    let db = if no_sync {
        // For local-only mode, use a simple local database connection
        info!("Using local-only database connection");
        Builder::new_local(db_path)
            .build()
            .await
            .context("Failed to create local database")?
    } else {
        // For sync mode, use the remote replica
        info!("Using synced database connection");
        Builder::new_remote_replica(db_path, url.to_string(), token.to_string())
            .build()
            .await
            .context("Failed to create synced database")?
    };
    
    let conn = db.connect().context("Failed to get connection")?;
    
    // Apply diff to local replica database
    info!("Applying diff to local replica database");
    
    // Check if we need to batch the operations
    let statements: Vec<&str> = diff_sql.split(';').collect();
    let non_empty_statements: Vec<&str> = statements
        .iter()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty() && *s != "BEGIN TRANSACTION" && *s != "COMMIT")
        .collect();
    
    let statement_count = non_empty_statements.len();
    
    // Analyze and group statements by type for batch execution
    info!("Analyzing {} statements for batch optimization...", statement_count);
    
    let mut create_statements = Vec::new();
    let mut delete_statements = Vec::new();
    let mut insert_statements = Vec::new();
    let mut other_statements = Vec::new();
    
    for statement in &non_empty_statements {
        let trimmed = statement.trim();
        if trimmed.starts_with("CREATE") {
            create_statements.push(make_create_statement_idempotent(statement));
        } else if trimmed.starts_with("DELETE FROM email_schedules WHERE id=") {
            delete_statements.push(statement.to_string());
        } else if trimmed.starts_with("INSERT INTO email_schedules") {
            insert_statements.push(statement.to_string());
        } else {
            other_statements.push(statement.to_string());
        }
    }
    
    info!("Statement grouping complete:");
    info!("  - CREATE statements: {}", create_statements.len());
    info!("  - DELETE statements: {}", delete_statements.len());
    info!("  - INSERT statements: {}", insert_statements.len());
    info!("  - Other statements: {}", other_statements.len());
    
    info!("Starting optimized execution...");
    let execution_start = std::time::Instant::now();
    
    // Execute CREATE statements first (usually just a few)
    if !create_statements.is_empty() {
        info!("Executing {} CREATE statements...", create_statements.len());
        for (i, statement) in create_statements.iter().enumerate() {
            info!("CREATE {}/{}: {}", i + 1, create_statements.len(),
                  if statement.len() > 100 { format!("{}...", &statement[..100]) } else { statement.to_string() });
            conn.execute(statement, ())
                .await
                .with_context(|| format!("Failed to execute CREATE statement: {}", statement))?;
        }
        info!("✅ Completed {} CREATE statements", create_statements.len());
    }
    
    // Batch execute DELETE statements using execute_batch
    if !delete_statements.is_empty() {
        info!("Batch executing {} DELETE statements...", delete_statements.len());
        let batch_size = 1000; // Much larger batch for simple DELETEs
        let total_batches = (delete_statements.len() + batch_size - 1) / batch_size;
        
        for (batch_num, batch) in delete_statements.chunks(batch_size).enumerate() {
            info!("DELETE batch {}/{} ({} statements)", batch_num + 1, total_batches, batch.len());
            
            // Join statements with semicolons for batch execution
            let batch_sql = batch.join(";\n") + ";";
            
            conn.execute_batch(&batch_sql)
                .await
                .with_context(|| format!("Failed to execute DELETE batch {}", batch_num + 1))?;
                
            info!("✅ Completed DELETE batch {}/{}", batch_num + 1, total_batches);
        }
        info!("✅ Completed {} DELETE statements", delete_statements.len());
    }
    
    // Batch execute INSERT statements using execute_batch
    if !insert_statements.is_empty() {
        info!("Batch executing {} INSERT statements...", insert_statements.len());
        let batch_size = 500; // Moderate batch size for INSERTs (they're larger)
        let total_batches = (insert_statements.len() + batch_size - 1) / batch_size;
        
        for (batch_num, batch) in insert_statements.chunks(batch_size).enumerate() {
            info!("INSERT batch {}/{} ({} statements)", batch_num + 1, total_batches, batch.len());
            
            // Join statements with semicolons for batch execution
            let batch_sql = batch.join(";\n") + ";";
            
            conn.execute_batch(&batch_sql)
                .await
                .with_context(|| format!("Failed to execute INSERT batch {}", batch_num + 1))?;
                
            info!("✅ Completed INSERT batch {}/{}", batch_num + 1, total_batches);
        }
        info!("✅ Completed {} INSERT statements", insert_statements.len());
    }
    
    // Execute other statements individually (usually just a few)
    if !other_statements.is_empty() {
        info!("Executing {} other statements individually...", other_statements.len());
        for (i, statement) in other_statements.iter().enumerate() {
            info!("OTHER {}/{}: {}", i + 1, other_statements.len(),
                  if statement.len() > 100 { format!("{}...", &statement[..100]) } else { statement.to_string() });
            conn.execute(statement, ())
                .await
                .with_context(|| format!("Failed to execute statement: {}", statement))?;
        }
        info!("✅ Completed {} other statements", other_statements.len());
    }
    
    let execution_duration = execution_start.elapsed();
    info!("Successfully applied {} statements to local replica database in {:.2}s", 
          statement_count, execution_duration.as_secs_f64());
    
    // Sync to Turso if not skipped
    if !no_sync {
        info!("Syncing changes to Turso...");
        db.sync().await.context("Failed to sync to Turso")?;
        info!("Successfully synced to Turso");
    } else {
        info!("Skipping sync to Turso (--no-sync flag set)");
    }
    
    Ok(())
}

/// Initialize and sync a database using offline sync capabilities
async fn offline_sync(
    db_path: &str,
    url: &str,
    token: &str,
    direction: &str,
) -> Result<()> {
    info!("Performing offline sync for database: {}", db_path);
    info!("Direction: {}", direction);
    
    // Create synced database (will create if it doesn't exist)
    let db = Builder::new_remote_replica(db_path, url.to_string(), token.to_string())
        .build()
        .await
        .context("Failed to create synced database")?;
    
    match direction {
        "pull" => {
            info!("Pulling changes from remote to local database");
            db.sync().await.context("Failed to sync from remote")?;
            info!("Successfully pulled changes from remote");
        }
        "push" => {
            info!("Pushing changes from local to remote database");
            db.sync().await.context("Failed to sync to remote")?;
            info!("Successfully pushed changes to remote");
        }
        "both" | _ => {
            info!("Syncing bidirectionally (pull and push)");
            db.sync().await.context("Failed to sync bidirectionally")?;
            info!("Successfully synced bidirectionally");
        }
    }
    
    // Show database stats
    let conn = db.connect().context("Failed to get connection")?;
    
    // Try to get table count as a basic health check
    match conn.query("SELECT name FROM sqlite_master WHERE type='table'", ()).await {
        Ok(mut results) => {
            let mut table_count = 0;
            while let Some(_row) = results.next().await.unwrap_or(None) {
                table_count += 1;
            }
            info!("Local database contains {} tables", table_count);
        }
        Err(e) => {
            warn!("Could not query database schema: {}", e);
        }
    }
    
    Ok(())
}

/// Run the full workflow with periodic syncing
async fn run_workflow(
    replica_path: &str,
    working_path: &str,
    url: &str,
    token: &str,
    sync_interval: u64,
) -> Result<()> {
    info!("Starting Turso sync workflow");
    info!("Replica: {}, Working: {}, Sync interval: {}s", 
          replica_path, working_path, sync_interval);
    
    // Initial sync and copy
    sync_from_turso(replica_path, url, token).await?;
    copy_database(replica_path, working_path)?;
    
    info!("Initial setup complete. OCaml can now use: {}", working_path);
    info!("Run 'turso-sync push' when ready to sync changes back to Turso");
    
    // Periodic sync from Turso (in case of external changes)
    let mut interval = tokio::time::interval(Duration::from_secs(sync_interval));
    
    loop {
        interval.tick().await;
        
        info!("Performing periodic sync from Turso...");
        if let Err(e) = sync_from_turso(replica_path, url, token).await {
            warn!("Periodic sync failed: {}", e);
        } else {
            info!("Periodic sync completed");
        }
    }
}

/// Bidirectional sync with Turso using libSQL sync (pulls and pushes changes)
async fn libsql_sync(
    db_path: &str,
    url: &str,
    token: &str,
) -> Result<()> {
    info!("Starting bidirectional sync with Turso");
    info!("Local database: {}", db_path);
    info!("Remote URL: {}", url);
    
    // Create synced database connection
    let db = Builder::new_synced_database(db_path, url.to_string(), token.to_string())
        .build()
        .await
        .context("Failed to create synced database connection")?;
    
    let conn = db.connect().context("Failed to get database connection")?;
    
    // First sync: Pull any remote changes to local
    info!("📥 Syncing from remote to local...");
    db.sync().await.context("Failed to sync from remote")?;
    info!("✅ Successfully pulled changes from remote");
    
    // Show current database state
    match conn.query("SELECT COUNT(*) as count FROM sqlite_master WHERE type='table'", ()).await {
        Ok(mut results) => {
            if let Some(row) = results.next().await.unwrap_or(None) {
                let table_count: i64 = row.get(0).unwrap_or(0);
                info!("📊 Local database contains {} tables", table_count);
            }
        }
        Err(e) => {
            warn!("Could not query database schema: {}", e);
        }
    }
    
    // Second sync: Push any local changes to remote
    info!("📤 Syncing from local to remote...");
    db.sync().await.context("Failed to sync to remote")?;
    info!("✅ Successfully pushed changes to remote");
    
    info!("🎉 Bidirectional sync completed successfully!");
    
    Ok(())
} 