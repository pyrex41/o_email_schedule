use libsql::Builder;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize logging to see what's happening
    env_logger::init();

    let db = if let Ok(url) = std::env::var("LIBSQL_URL") {
        let token = std::env::var("LIBSQL_AUTH_TOKEN").unwrap_or_else(|_| {
            println!("LIBSQL_AUTH_TOKEN not set, using empty token...");
            String::new()
        });

        println!("Connecting to remote Turso database...");
        println!("URL: {}", url);
        println!("Token: {}", if token.is_empty() { "empty" } else { "provided" });

        // KEY CHANGE 1: Use new_remote_replica instead of new_remote for better reliability
        // This creates a local replica that syncs with the remote database
        Builder::new_remote_replica("local_replica.db", url, token)
            .build()
            .await?
    } else {
        println!("LIBSQL_URL not set, using in-memory database...");
        Builder::new_local(":memory:")
            .build()
            .await?
    };

    let conn = db.connect()?;

    // KEY CHANGE 2: Don't execute multiple SQL statements in a single query()
    // Use execute_batch() for multiple statements
    println!("Testing basic queries...");
    conn.execute_batch("SELECT 1; SELECT 1;").await?;

    // Create table
    println!("Creating users table...");
    conn.execute("CREATE TABLE IF NOT EXISTS users (email TEXT)", ())
        .await?;

    // Insert data using prepared statement
    println!("Inserting test user...");
    let mut stmt = conn
        .prepare("INSERT INTO users (email) VALUES (?1)")
        .await?;

    stmt.execute(["foo@example.com"]).await?;

    // Query data using prepared statement
    println!("Querying test user...");
    let mut stmt = conn
        .prepare("SELECT * FROM users WHERE email = ?1")
        .await?;

    let mut rows = stmt.query(["foo@example.com"]).await?;

    if let Some(row) = rows.next().await? {
        // KEY CHANGE 3: Use row.get::<Type>(index) instead of row.get_value(index)
        let email: String = row.get(0)?;
        println!("Found user: {}", email);
    } else {
        println!("No user found!");
    }

    // If using remote replica, sync with remote
    if std::env::var("LIBSQL_URL").is_ok() {
        println!("Syncing with remote database...");
        db.sync().await?;
        println!("Sync completed successfully!");
    }

    println!("✅ All operations completed successfully!");
    
    Ok(())
} 