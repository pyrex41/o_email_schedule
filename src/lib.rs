use ocaml_interop::{
    ocaml_export, BoxRoot, OCaml, OCamlFloat, OCamlInt, OCamlList, OCamlRuntime, ToOCaml,
    FromOCaml, DynBox, OCamlBytes
};
use anyhow::{Context, Result};
use libsql::{Builder, Connection, Database};
use std::sync::{Arc, Mutex};
use std::collections::HashMap;
use tokio::runtime::Runtime;

// Global state for managing database connections
static mut RUNTIME: Option<Runtime> = None;
static mut CONNECTIONS: Option<Mutex<HashMap<String, Arc<Database>>>> = None;

// Initialize the async runtime (call once from OCaml)
#[ocaml_export]
fn turso_init_runtime() -> OCaml<()> {
    unsafe {
        if RUNTIME.is_none() {
            RUNTIME = Some(Runtime::new().expect("Failed to create Tokio runtime"));
            CONNECTIONS = Some(Mutex::new(HashMap::new()));
        }
    }
    OCaml::unit()
}

// Create a synced database connection to Turso
#[ocaml_export]
fn turso_create_synced_db(
    cr: &mut OCamlRuntime,
    db_path: OCaml<String>,
    url: OCaml<String>,
    token: OCaml<String>,
) -> OCaml<Result<String, String>> {
    let db_path: String = db_path.to_rust(cr);
    let url: String = url.to_rust(cr);
    let token: String = token.to_rust(cr);
    
    let rt = unsafe { RUNTIME.as_ref().expect("Runtime not initialized") };
    
    let result = rt.block_on(async {
        match Builder::new_remote_replica(&db_path, url, token).build().await {
            Ok(db) => {
                let arc_db = Arc::new(db);
                let mut connections = unsafe {
                    CONNECTIONS.as_ref().expect("Connections not initialized").lock().unwrap()
                };
                let connection_id = format!("conn_{}", connections.len());
                connections.insert(connection_id.clone(), arc_db);
                Ok(connection_id)
            }
            Err(e) => Err(format!("Failed to create database: {}", e))
        }
    });
    
    result.to_ocaml(cr)
}

// Sync the database with remote
#[ocaml_export]
fn turso_sync(
    cr: &mut OCamlRuntime,
    connection_id: OCaml<String>,
) -> OCaml<Result<(), String>> {
    let connection_id: String = connection_id.to_rust(cr);
    
    let rt = unsafe { RUNTIME.as_ref().expect("Runtime not initialized") };
    
    let result = rt.block_on(async {
        let connections = unsafe {
            CONNECTIONS.as_ref().expect("Connections not initialized").lock().unwrap()
        };
        
        match connections.get(&connection_id) {
            Some(db) => {
                match db.sync().await {
                    Ok(()) => Ok(()),
                    Err(e) => Err(format!("Sync failed: {}", e))
                }
            }
            None => Err("Connection not found".to_string())
        }
    });
    
    result.to_ocaml(cr)
}

// Execute a SQL query and return results as a list of lists
#[ocaml_export]
fn turso_query(
    cr: &mut OCamlRuntime,
    connection_id: OCaml<String>,
    sql: OCaml<String>,
) -> OCaml<Result<Vec<Vec<String>>, String>> {
    let connection_id: String = connection_id.to_rust(cr);
    let sql: String = sql.to_rust(cr);
    
    let rt = unsafe { RUNTIME.as_ref().expect("Runtime not initialized") };
    
    let result = rt.block_on(async {
        let connections = unsafe {
            CONNECTIONS.as_ref().expect("Connections not initialized").lock().unwrap()
        };
        
        match connections.get(&connection_id) {
            Some(db) => {
                match db.connect() {
                    Ok(conn) => execute_query_internal(&conn, &sql).await,
                    Err(e) => Err(format!("Connection failed: {}", e))
                }
            }
            None => Err("Connection not found".to_string())
        }
    });
    
    result.to_ocaml(cr)
}

// Execute a SQL statement (INSERT, UPDATE, DELETE) without returning results
#[ocaml_export]
fn turso_execute(
    cr: &mut OCamlRuntime,
    connection_id: OCaml<String>,
    sql: OCaml<String>,
) -> OCaml<Result<i64, String>> {
    let connection_id: String = connection_id.to_rust(cr);
    let sql: String = sql.to_rust(cr);
    
    let rt = unsafe { RUNTIME.as_ref().expect("Runtime not initialized") };
    
    let result = rt.block_on(async {
        let connections = unsafe {
            CONNECTIONS.as_ref().expect("Connections not initialized").lock().unwrap()
        };
        
        match connections.get(&connection_id) {
            Some(db) => {
                match db.connect() {
                    Ok(conn) => execute_statement_internal(&conn, &sql).await,
                    Err(e) => Err(format!("Connection failed: {}", e))
                }
            }
            None => Err("Connection not found".to_string())
        }
    });
    
    result.to_ocaml(cr)
}

// Execute a batch of SQL statements as a transaction
#[ocaml_export]
fn turso_execute_batch(
    cr: &mut OCamlRuntime,
    connection_id: OCaml<String>,
    sql_statements: OCaml<Vec<String>>,
) -> OCaml<Result<i64, String>> {
    let connection_id: String = connection_id.to_rust(cr);
    let sql_statements: Vec<String> = sql_statements.to_rust(cr);
    
    let rt = unsafe { RUNTIME.as_ref().expect("Runtime not initialized") };
    
    let result = rt.block_on(async {
        let connections = unsafe {
            CONNECTIONS.as_ref().expect("Connections not initialized").lock().unwrap()
        };
        
        match connections.get(&connection_id) {
            Some(db) => {
                match db.connect() {
                    Ok(conn) => execute_batch_internal(&conn, &sql_statements).await,
                    Err(e) => Err(format!("Connection failed: {}", e))
                }
            }
            None => Err("Connection not found".to_string())
        }
    });
    
    result.to_ocaml(cr)
}

// Close and remove a database connection
#[ocaml_export]
fn turso_close_connection(
    cr: &mut OCamlRuntime,
    connection_id: OCaml<String>,
) -> OCaml<Result<(), String>> {
    let connection_id: String = connection_id.to_rust(cr);
    
    let mut connections = unsafe {
        CONNECTIONS.as_ref().expect("Connections not initialized").lock().unwrap()
    };
    
    match connections.remove(&connection_id) {
        Some(_) => Ok(()).to_ocaml(cr),
        None => Err("Connection not found".to_string()).to_ocaml(cr)
    }
}

// Helper function to execute a query and return results
async fn execute_query_internal(conn: &Connection, sql: &str) -> Result<Vec<Vec<String>>, String> {
    match conn.query(sql, ()).await {
        Ok(mut rows) => {
            let mut results = Vec::new();
            while let Some(row) = rows.next().await.map_err(|e| format!("Row iteration error: {}", e))? {
                let mut row_data = Vec::new();
                let column_count = row.column_count();
                
                for i in 0..column_count {
                    let value = row.get_value(i).map_err(|e| format!("Column access error: {}", e))?;
                    let string_value = match value {
                        libsql::Value::Null => String::new(),
                        libsql::Value::Integer(i) => i.to_string(),
                        libsql::Value::Real(f) => f.to_string(),
                        libsql::Value::Text(s) => s,
                        libsql::Value::Blob(b) => format!("BLOB({} bytes)", b.len()),
                    };
                    row_data.push(string_value);
                }
                results.push(row_data);
            }
            Ok(results)
        }
        Err(e) => Err(format!("Query failed: {}", e))
    }
}

// Helper function to execute a statement and return affected rows
async fn execute_statement_internal(conn: &Connection, sql: &str) -> Result<i64, String> {
    match conn.execute(sql, ()).await {
        Ok(rows_affected) => Ok(rows_affected as i64),
        Err(e) => Err(format!("Execute failed: {}", e))
    }
}

// Helper function to execute a batch of statements as a transaction
async fn execute_batch_internal(conn: &Connection, sql_statements: &[String]) -> Result<i64, String> {
    // Begin transaction
    if let Err(e) = conn.execute("BEGIN TRANSACTION", ()).await {
        return Err(format!("Failed to begin transaction: {}", e));
    }
    
    let mut total_affected = 0i64;
    
    // Execute each statement
    for (i, sql) in sql_statements.iter().enumerate() {
        match conn.execute(sql, ()).await {
            Ok(affected) => total_affected += affected as i64,
            Err(e) => {
                // Rollback on error
                let _ = conn.execute("ROLLBACK", ()).await;
                return Err(format!("Statement {} failed: {} (rolled back)", i + 1, e));
            }
        }
    }
    
    // Commit transaction
    match conn.execute("COMMIT", ()).await {
        Ok(_) => Ok(total_affected),
        Err(e) => {
            let _ = conn.execute("ROLLBACK", ()).await;
            Err(format!("Failed to commit transaction: {} (rolled back)", e))
        }
    }
}

// Get connection statistics (for debugging/monitoring)
#[ocaml_export]
fn turso_connection_count(cr: &mut OCamlRuntime) -> OCaml<i32> {
    let connections = unsafe {
        CONNECTIONS.as_ref().expect("Connections not initialized").lock().unwrap()
    };
    
    (connections.len() as i32).to_ocaml(cr)
}

// Initialize the OCaml runtime (this must be called from OCaml)
ocaml_interop::ocaml_runtime!(turso_ocaml_ffi);