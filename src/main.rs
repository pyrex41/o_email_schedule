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

    /// Initialize local database using dump from Turso (no embedded replica)
    DumpInit {
        /// Path to local working database
        #[arg(short, long, default_value = "working_copy.db")]
        db_path: String,
        
        /// Turso database URL
        #[arg(short, long)]
        url: Option<String>,
        
        /// Turso auth token
        #[arg(short, long)]
        token: Option<String>,
    },

    /// Push changes to Turso using dump-based workflow with batched execution
    DumpPush {
        /// Path to local working database
        #[arg(short, long, default_value = "working_copy.db")]
        db_path: String,
        
        /// Path to original dump file for comparison
        #[arg(long, default_value = "original_dump.sql")]
        original_dump: String,
        
        /// Turso database URL
        #[arg(short, long)]
        url: Option<String>,
        
        /// Turso auth token
        #[arg(short, long)]
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
    
    /// Full workflow: sync -> copy -> ready for manual syncs
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

    /// Test connection to Turso using official docs patterns
    Test {
        /// Turso database URL
        #[arg(short, long)]
        url: Option<String>,

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
        Commands::DumpInit { db_path, url, token } => {
            let url = get_env_or_arg(url, "TURSO_DATABASE_URL")?;
            let token = get_env_or_arg(token, "TURSO_AUTH_TOKEN")?;
            dump_init(&db_path, &url, &token).await?;
        }
        Commands::DumpPush { db_path, original_dump, url, token, diff_file } => {
            let url = get_env_or_arg(url, "TURSO_DATABASE_URL")?;
            let token = get_env_or_arg(token, "TURSO_AUTH_TOKEN")?;
            dump_push(&db_path, &original_dump, &url, &token, &diff_file).await?;
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
        Commands::Workflow { replica_path, working_path, url, token } => {
            let url = get_env_or_arg(url, "TURSO_DATABASE_URL")?;
            let token = get_env_or_arg(token, "TURSO_AUTH_TOKEN")?;
            run_workflow(&replica_path, &working_path, &url, &token).await?;
        }
        Commands::LibsqlSync { db_path, sync_url, token } => {
            let url = get_env_or_arg(sync_url, "TURSO_DATABASE_URL")?;
            let token = get_env_or_arg(token, "TURSO_AUTH_TOKEN")?;
            libsql_sync(&db_path, &url, &token).await?;
        }
        Commands::Test { url, token } => {
            // Set environment variables if provided
            if let Some(url) = url {
                env::set_var("LIBSQL_URL", url);
            }
            if let Some(token) = token {
                env::set_var("LIBSQL_AUTH_TOKEN", token);
            }
            test_connection().await?;
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
    
    // Apply diff to Turso with batching for large diffs - use replica for reliability
    info!("Applying changes to Turso using temporary replica");
    let temp_push_replica = "temp_push_replica.db";
    let db = Builder::new_remote_replica(temp_push_replica, url.to_string(), token.to_string())
        .build()
        .await
        .context("Failed to create remote replica for push")?;
    
    // Sync to get latest remote state first
    info!("Syncing replica with remote before applying changes...");
    db.sync().await.context("Failed to sync replica before push")?;
    
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
    
    info!("Successfully applied changes to replica");
    
    // Sync changes to remote
    info!("Syncing applied changes to remote database...");
    db.sync().await.context("Failed to sync changes to remote")?;
    info!("Successfully synced changes to remote");
    
    // Clean up temporary replica file
    let _ = fs::remove_file(temp_push_replica);
    
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
        // For sync mode, use the synced database with offline sync capabilities
        info!("Using synced database connection with offline sync");
        Builder::new_synced_database(db_path, url.to_string(), token.to_string())
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
    
    // Batch execute DELETE statements with large batches
    if !delete_statements.is_empty() {
        info!("Batch executing {} DELETE statements...", delete_statements.len());
        let batch_size = 2000; // Much larger batches for better throughput
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
    
    // Batch execute INSERT statements with large batches
    if !insert_statements.is_empty() {
        info!("Batch executing {} INSERT statements...", insert_statements.len());
        let batch_size = 1000; // Much larger batches to reduce network round trips
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
    
    // Create synced database with proper offline sync capabilities
    let db = Builder::new_synced_database(db_path, url.to_string(), token.to_string())
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

/// Run the initial workflow setup without periodic syncing
async fn run_workflow(
    replica_path: &str,
    working_path: &str,
    url: &str,
    token: &str,
) -> Result<()> {
    info!("Starting Turso sync workflow");
    info!("Replica: {}, Working: {}", 
          replica_path, working_path);
    
    // Initial sync and copy
    sync_from_turso(replica_path, url, token).await?;
    copy_database(replica_path, working_path)?;
    
    info!("✅ Initial setup complete!");
    info!("📁 Your OCaml application can now use: {}", working_path);
    info!("");
    info!("🔄 Manual sync commands:");
    info!("  • Pull latest changes: turso-sync sync --replica-path {}", replica_path);
    info!("  • Push your changes: turso-sync push --replica-path {} --working-path {}", replica_path, working_path);
    info!("  • Bidirectional sync: turso-sync libsql-sync --db-path {}", working_path);
    info!("  • Apply diff file: turso-sync apply-diff --db-path {} --diff-file diff.sql", replica_path);
    info!("");
    info!("💡 Recommended: Use 'turso-sync libsql-sync' for automatic bidirectional sync");
    
    Ok(())
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

/// Initialize local database using dump from Turso (no embedded replica)
async fn dump_init(db_path: &str, url: &str, token: &str) -> Result<()> {
    info!("Initializing local database using dump from Turso: {}", db_path);
    
    // Connect to remote Turso database for dump extraction (no sync needed)
    let db = Builder::new_remote(url.to_string(), token.to_string())
        .build()
        .await
        .context("Failed to connect to Turso database")?;
    
    let conn = db.connect().context("Failed to get connection")?;
    
    // Execute .dump command to get SQL dump
    info!("Executing .dump command on remote database...");
    let dump_sql = get_database_dump(&conn).await
        .context("Failed to get database dump")?;
    
    info!("Retrieved database dump: {} bytes", dump_sql.len());
    
    // Save the original dump for debugging/reference
    let original_dump_path = "original_dump.sql";
    fs::write(original_dump_path, &dump_sql)
        .context("Failed to write original dump file")?;
    info!("Saved original dump to: {}", original_dump_path);
    
    // Create baseline database from dump (this will be our fast-copy source)
    let baseline_db_path = "baseline.db";
    info!("Creating baseline database from dump...");
    let baseline_start = std::time::Instant::now();
    create_db_from_dump(&dump_sql, baseline_db_path)
        .context("Failed to create baseline database from dump")?;
    let baseline_duration = baseline_start.elapsed();
    info!("Created baseline database in {:.2}s", baseline_duration.as_secs_f64());
    
    // Copy baseline to working copy (fast file copy)
    info!("Copying baseline to working copy...");
    let copy_start = std::time::Instant::now();
    copy_database(baseline_db_path, db_path)?;
    let copy_duration = copy_start.elapsed();
    info!("Copied to working copy in {:.2}s", copy_duration.as_secs_f64());
    
    info!("✅ Successfully initialized local databases:");
    info!("📄 Baseline database: {}", baseline_db_path);
    info!("🚀 Working copy for OCaml: {}", db_path);
    info!("💾 Original dump saved as: {}", original_dump_path);
    
    Ok(())
}

/// Push changes to Turso using dump-based workflow with batched execution
async fn dump_push(
    db_path: &str,
    original_dump_path: &str,
    url: &str,
    token: &str,
    diff_file: &str,
) -> Result<()> {
    info!("Pushing changes to Turso using dump-based workflow");
    
    // Check if local database exists
    if !Path::new(db_path).exists() {
        return Err(anyhow::anyhow!("Local database {} does not exist", db_path));
    }
    
    // Check if baseline database exists
    let baseline_db_path = "baseline.db";
    if !Path::new(baseline_db_path).exists() {
        return Err(anyhow::anyhow!("Baseline database {} does not exist. Run dump-init first.", baseline_db_path));
    }
    
    // Create a temporary database by copying baseline (fast file copy)
    let temp_original_db = "temp_original.db";
    
    info!("Copying baseline database for comparison...");
    let copy_start = std::time::Instant::now();
    copy_database(baseline_db_path, temp_original_db)
        .context("Failed to copy baseline database")?;
    let copy_duration = copy_start.elapsed();
    info!("Copied baseline database in {:.2}s", copy_duration.as_secs_f64());
    
    // Generate diff using sqldiff
    info!("Generating diff using sqldiff: {} vs {}", temp_original_db, db_path);
    let sqldiff_start = std::time::Instant::now();
    let output = Command::new("sqldiff")
        .arg("--transaction")
        .arg(temp_original_db)
        .arg(db_path)
        .output()
        .context("Failed to run sqldiff - make sure it's installed and in PATH")?;
    let sqldiff_duration = sqldiff_start.elapsed();
    info!("sqldiff completed in {:.2}s", sqldiff_duration.as_secs_f64());
    
    // Clean up temporary database
    let _ = fs::remove_file(temp_original_db);
    
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
    
    // Apply diff to remote Turso database using batching
    info!("Applying changes to Turso with batched execution");
    let apply_start = std::time::Instant::now();
    apply_diff_to_remote(&diff_sql, url, token).await
        .context("Failed to apply diff to remote database")?;
    let apply_duration = apply_start.elapsed();
    info!("Applied diff to remote database in {:.2}s", apply_duration.as_secs_f64());
    
    // Update the baseline database to reflect current remote state
    info!("Updating baseline database to current remote state...");
    let update_start = std::time::Instant::now();
    let conn = Builder::new_remote(url.to_string(), token.to_string())
        .build()
        .await
        .context("Failed to connect to Turso database")?
        .connect()
        .context("Failed to get connection for baseline update")?;
    
    let updated_dump = get_database_dump(&conn).await
        .context("Failed to get updated database dump")?;
    
    // Create new baseline database from updated dump
    create_db_from_dump(&updated_dump, baseline_db_path)
        .context("Failed to update baseline database")?;
    
    // Also update the dump file for reference
    fs::write(original_dump_path, &updated_dump)
        .context("Failed to update original dump file")?;
    
    let update_duration = update_start.elapsed();
    info!("Updated baseline database and dump ({} bytes) in {:.2}s", updated_dump.len(), update_duration.as_secs_f64());
    
    info!("✅ Successfully pushed changes to Turso");
    info!("📄 Updated baseline database: {}", baseline_db_path);
    info!("📄 Updated dump file: {}", original_dump_path);
    
    Ok(())
}

/// Get database dump by querying all tables and data
async fn get_database_dump(conn: &libsql::Connection) -> Result<String> {
    let mut dump = String::new();
    
    // Get all table creation statements
    let mut table_results = conn.query(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        ()
    ).await.context("Failed to query table schemas")?;
    
    let mut create_statements = Vec::new();
    while let Some(row) = table_results.next().await.context("Failed to fetch table row")? {
        if let Ok(sql) = row.get::<String>(0) {
            if !sql.is_empty() {
                create_statements.push(sql);
            }
        }
    }
    
    // Add CREATE TABLE statements
    for create_sql in &create_statements {
        dump.push_str(&create_sql);
        dump.push_str(";\n");
    }
    
    // Get all table names for data dumping
    let mut table_names = Vec::new();
    let mut name_results = conn.query(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        ()
    ).await.context("Failed to query table names")?;
    
    while let Some(row) = name_results.next().await.context("Failed to fetch table name")? {
        if let Ok(name) = row.get::<String>(0) {
            table_names.push(name);
        }
    }
    
    // Dump data for each table
    for table_name in table_names {
        // Get column information
        let mut column_results = conn.query(
            &format!("PRAGMA table_info({})", table_name),
            ()
        ).await.context("Failed to get table info")?;
        
        let mut columns = Vec::new();
        while let Some(row) = column_results.next().await.context("Failed to fetch column info")? {
            if let Ok(col_name) = row.get::<String>(1) {
                columns.push(col_name);
            }
        }
        
        if columns.is_empty() {
            continue;
        }
        
        // Dump table data
        let select_sql = format!("SELECT * FROM {}", table_name);
        let mut data_results = conn.query(&select_sql, ())
            .await.with_context(|| format!("Failed to select from table {}", table_name))?;
        
        while let Some(row) = data_results.next().await
            .with_context(|| format!("Failed to fetch row from table {}", table_name))? {
            
            let mut values = Vec::new();
            for i in 0..columns.len() {
                match row.get::<libsql::Value>(i as i32) {
                    Ok(libsql::Value::Null) => values.push("NULL".to_string()),
                    Ok(libsql::Value::Integer(n)) => values.push(n.to_string()),
                    Ok(libsql::Value::Real(f)) => values.push(f.to_string()),
                    Ok(libsql::Value::Text(s)) => values.push(format!("'{}'", s.replace("'", "''"))),
                    Ok(libsql::Value::Blob(b)) => values.push(format!("X'{}'", hex::encode(b))),
                    Err(_) => values.push("NULL".to_string()),
                }
            }
            
            dump.push_str(&format!(
                "INSERT INTO {} ({}) VALUES ({});\n",
                table_name,
                columns.join(", "),
                values.join(", ")
            ));
        }
    }
    
    // Get index creation statements
    let mut index_results = conn.query(
        "SELECT sql FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%' AND sql IS NOT NULL ORDER BY name",
        ()
    ).await.context("Failed to query index schemas")?;
    
    while let Some(row) = index_results.next().await.context("Failed to fetch index row")? {
        if let Ok(sql) = row.get::<String>(0) {
            if !sql.is_empty() {
                dump.push_str(&sql);
                dump.push_str(";\n");
            }
        }
    }
    
    Ok(dump)
}

/// Create local SQLite database from SQL dump
fn create_db_from_dump(dump_sql: &str, db_path: &str) -> Result<()> {
    // Remove existing database if it exists
    if Path::new(db_path).exists() {
        fs::remove_file(db_path)
            .with_context(|| format!("Failed to remove existing database {}", db_path))?;
    }
    
    // Use sqlite3 command to create database from dump
    let mut cmd = Command::new("sqlite3")
        .arg(db_path)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .context("Failed to spawn sqlite3 command - make sure sqlite3 is installed and in PATH")?;
    
    // Write dump SQL to stdin
    if let Some(stdin) = cmd.stdin.as_mut() {
        use std::io::Write;
        stdin.write_all(dump_sql.as_bytes())
            .context("Failed to write dump to sqlite3 stdin")?;
    }
    
    let output = cmd.wait_with_output()
        .context("Failed to wait for sqlite3 command")?;
    
    if !output.status.success() {
        error!("sqlite3 failed: {}", String::from_utf8_lossy(&output.stderr));
        return Err(anyhow::anyhow!("sqlite3 command failed"));
    }
    
    info!("Successfully created database: {}", db_path);
    Ok(())
}

/// Apply diff to remote database with optimized batching and timeout handling
async fn apply_diff_to_remote(diff_sql: &str, url: &str, token: &str) -> Result<()> {
    info!("Applying diff to remote Turso database with optimized batching");
    
    // Use direct remote connection for pure dump-based workflow
    let db = Builder::new_remote(url.to_string(), token.to_string())
        .build()
        .await
        .context("Failed to connect to Turso")?;
    
    let conn = db.connect().context("Failed to get connection")?;
    
    // Parse and group statements (reuse logic from apply_diff_to_turso)
    let statements: Vec<&str> = diff_sql.split(';').collect();
    let non_empty_statements: Vec<&str> = statements
        .iter()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty() && *s != "BEGIN TRANSACTION" && *s != "COMMIT")
        .collect();
    
    let statement_count = non_empty_statements.len();
    info!("Analyzing {} statements for batched execution...", statement_count);
    
    // Group statements by type
    let mut create_statements = Vec::new();
    let mut delete_statements = Vec::new();
    let mut insert_statements = Vec::new();
    let mut other_statements = Vec::new();
    
    for statement in &non_empty_statements {
        let trimmed = statement.trim();
        if trimmed.starts_with("CREATE") {
            create_statements.push(make_create_statement_idempotent(statement));
        } else if trimmed.starts_with("DELETE") {
            delete_statements.push(statement.to_string());
        } else if trimmed.starts_with("INSERT") {
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
    
    let execution_start = std::time::Instant::now();
    
    // Execute CREATE statements first (individual execution for safety)
    if !create_statements.is_empty() {
        info!("Executing {} CREATE statements individually...", create_statements.len());
        for (i, statement) in create_statements.iter().enumerate() {
            info!("CREATE {}/{}: {}", i + 1, create_statements.len(),
                  if statement.len() > 100 { format!("{}...", &statement[..100]) } else { statement.to_string() });
            
            match tokio::time::timeout(Duration::from_secs(10), conn.execute(statement, ())).await {
                Ok(Ok(_)) => {},
                Ok(Err(e)) => return Err(e).with_context(|| format!("Failed to execute CREATE statement: {}", statement)),
                Err(_) => return Err(anyhow::anyhow!("CREATE statement timed out: {}", statement)),
            }
        }
        info!("✅ Completed {} CREATE statements", create_statements.len());
    }
    
    // Batch execute DELETE statements with large batches
    if !delete_statements.is_empty() {
        info!("Batch executing {} DELETE statements...", delete_statements.len());
        let batch_size = 2000; // Much larger batches for better throughput
        let total_batches = (delete_statements.len() + batch_size - 1) / batch_size;
        
        for (batch_num, batch) in delete_statements.chunks(batch_size).enumerate() {
            info!("DELETE batch {}/{} ({} statements)", batch_num + 1, total_batches, batch.len());
            let batch_sql = batch.join(";\n") + ";";
            
            // Simple timeout with one retry
            match tokio::time::timeout(Duration::from_secs(15), conn.execute_batch(&batch_sql)).await {
                Ok(Ok(_)) => {
                    info!("✅ Completed DELETE batch {}/{}", batch_num + 1, total_batches);
                },
                Ok(Err(e)) => {
                    warn!("DELETE batch {} failed, retrying once: {}", batch_num + 1, e);
                    // One retry with shorter timeout
                    match tokio::time::timeout(Duration::from_secs(10), conn.execute_batch(&batch_sql)).await {
                        Ok(Ok(_)) => {
                            info!("✅ Completed DELETE batch {}/{} (retry)", batch_num + 1, total_batches);
                        },
                        Ok(Err(e)) => return Err(e).with_context(|| format!("Failed to execute DELETE batch {} after retry", batch_num + 1)),
                        Err(_) => return Err(anyhow::anyhow!("DELETE batch {} timed out after retry", batch_num + 1)),
                    }
                },
                Err(_) => {
                    warn!("DELETE batch {} timed out, retrying once", batch_num + 1);
                    match tokio::time::timeout(Duration::from_secs(10), conn.execute_batch(&batch_sql)).await {
                        Ok(Ok(_)) => {
                            info!("✅ Completed DELETE batch {}/{} (retry)", batch_num + 1, total_batches);
                        },
                        Ok(Err(e)) => return Err(e).with_context(|| format!("Failed to execute DELETE batch {} after timeout retry", batch_num + 1)),
                        Err(_) => return Err(anyhow::anyhow!("DELETE batch {} timed out twice", batch_num + 1)),
                    }
                }
            }
        }
        info!("✅ Completed {} DELETE statements", delete_statements.len());
    }
    
    // Batch execute INSERT statements with large batches
    if !insert_statements.is_empty() {
        info!("Batch executing {} INSERT statements...", insert_statements.len());
        let batch_size = 1000; // Much larger batches to reduce network round trips
        let total_batches = (insert_statements.len() + batch_size - 1) / batch_size;
        
        for (batch_num, batch) in insert_statements.chunks(batch_size).enumerate() {
            info!("INSERT batch {}/{} ({} statements)", batch_num + 1, total_batches, batch.len());
            let batch_sql = batch.join(";\n") + ";";
            
            // Simple timeout with one retry  
            match tokio::time::timeout(Duration::from_secs(20), conn.execute_batch(&batch_sql)).await {
                Ok(Ok(_)) => {
                    info!("✅ Completed INSERT batch {}/{}", batch_num + 1, total_batches);
                },
                Ok(Err(e)) => {
                    warn!("INSERT batch {} failed, retrying once: {}", batch_num + 1, e);
                    // One retry with shorter timeout
                    match tokio::time::timeout(Duration::from_secs(15), conn.execute_batch(&batch_sql)).await {
                        Ok(Ok(_)) => {
                            info!("✅ Completed INSERT batch {}/{} (retry)", batch_num + 1, total_batches);
                        },
                        Ok(Err(e)) => return Err(e).with_context(|| format!("Failed to execute INSERT batch {} after retry", batch_num + 1)),
                        Err(_) => return Err(anyhow::anyhow!("INSERT batch {} timed out after retry", batch_num + 1)),
                    }
                },
                Err(_) => {
                    warn!("INSERT batch {} timed out, retrying once", batch_num + 1);
                    match tokio::time::timeout(Duration::from_secs(15), conn.execute_batch(&batch_sql)).await {
                        Ok(Ok(_)) => {
                            info!("✅ Completed INSERT batch {}/{} (retry)", batch_num + 1, total_batches);
                        },
                        Ok(Err(e)) => return Err(e).with_context(|| format!("Failed to execute INSERT batch {} after timeout retry", batch_num + 1)),
                        Err(_) => return Err(anyhow::anyhow!("INSERT batch {} timed out twice", batch_num + 1)),
                    }
                }
            }
        }
        info!("✅ Completed {} INSERT statements", insert_statements.len());
    }
    
    // Execute other statements individually
    if !other_statements.is_empty() {
        info!("Executing {} other statements individually...", other_statements.len());
        for (i, statement) in other_statements.iter().enumerate() {
            info!("OTHER {}/{}: {}", i + 1, other_statements.len(),
                  if statement.len() > 100 { format!("{}...", &statement[..100]) } else { statement.to_string() });
            
            match tokio::time::timeout(Duration::from_secs(10), conn.execute(statement, ())).await {
                Ok(Ok(_)) => {},
                Ok(Err(e)) => return Err(e).with_context(|| format!("Failed to execute statement: {}", statement)),
                Err(_) => return Err(anyhow::anyhow!("Statement timed out: {}", statement)),
            }
        }
        info!("✅ Completed {} other statements", other_statements.len());
    }
    
    let execution_duration = execution_start.elapsed();
    info!("Successfully applied {} statements to remote database in {:.2}s", 
          statement_count, execution_duration.as_secs_f64());
    
    info!("✅ Successfully applied all changes to remote database");
    Ok(())
}

/// Simple test function that follows Turso docs exactly
async fn test_connection() -> Result<()> {
    let db = if let Ok(url) = std::env::var("LIBSQL_URL") {
        let token = std::env::var("LIBSQL_AUTH_TOKEN").unwrap_or_else(|_| {
            println!("LIBSQL_AUTH_TOKEN not set, using empty token...");
            String::new()
        });

        // Use new_remote_replica for better reliability (as shown in docs)
        Builder::new_remote_replica("test_replica.db", url, token)
            .build()
            .await
            .context("Failed to build remote replica")?
    } else {
        Builder::new_local(":memory:")
            .build()
            .await
            .context("Failed to build local database")?
    };

    let conn = db.connect().context("Failed to connect to database")?;

    // Don't execute multiple statements in one query - use execute_batch instead
    conn.execute_batch("SELECT 1; SELECT 1;")
        .await
        .context("Failed to execute batch query")?;

    conn.execute("CREATE TABLE IF NOT EXISTS users (email TEXT)", ())
        .await
        .context("Failed to create table")?;

    let mut stmt = conn
        .prepare("INSERT INTO users (email) VALUES (?1)")
        .await
        .context("Failed to prepare insert statement")?;

    stmt.execute(["foo@example.com"])
        .await
        .context("Failed to execute insert")?;

    let mut stmt = conn
        .prepare("SELECT * FROM users WHERE email = ?1")
        .await
        .context("Failed to prepare select statement")?;

    let mut rows = stmt.query(["foo@example.com"])
        .await
        .context("Failed to execute select")?;

    if let Some(row) = rows.next().await.context("Failed to get next row")? {
        // Use get::<String>(0) instead of get_value(0) as shown in docs
        let email: String = row.get(0).context("Failed to get email value")?;
        println!("Row email: {}", email);
    }

    println!("✅ Connection test successful!");
    Ok(())
} 