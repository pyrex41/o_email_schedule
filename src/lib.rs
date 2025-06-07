use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::{Arc, Mutex};

use libsql::{Builder, Connection, Database};
use once_cell::sync::Lazy;
use serde::Serialize;
use tokio::runtime::Runtime;

// --- Global State ---
static RUNTIME: Lazy<Runtime> = Lazy::new(|| Runtime::new().expect("Failed to create Tokio runtime"));
static CONNECTIONS: Lazy<Mutex<HashMap<String, Arc<Database>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

// --- API Response Struct for JSON serialization ---
#[derive(Serialize)]
struct ApiResponse<T: Serialize> {
    data: Option<T>,
    error: Option<String>,
}

// --- Helper to convert a Result to a JSON string pointer ---
fn result_to_json_ptr<T: Serialize>(result: Result<T, String>) -> *mut c_char {
    let response = match result {
        Ok(data) => ApiResponse {
            data: Some(data),
            error: None,
        },
        Err(err) => ApiResponse {
            data: None,
            error: Some(err),
        },
    };
    // It's the responsibility of the caller to free this string.
    CString::new(serde_json::to_string(&response).unwrap())
        .unwrap()
        .into_raw()
}

// --- Memory Management ---
#[no_mangle]
pub extern "C" fn turso_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(s);
    }
}

// --- FFI Functions ---

#[no_mangle]
pub extern "C" fn turso_init_runtime() {
    // With once_cell, initialization is lazy and happens on first access.
    // We can call this to eagerly initialize, but it's not strictly necessary.
    Lazy::force(&RUNTIME);
    Lazy::force(&CONNECTIONS);
}

// Helper to safely get string from pointer
fn ptr_to_string(ptr: *const c_char) -> Result<String, String> {
    if ptr.is_null() {
        return Err("Null pointer passed to FFI function".to_string());
    }
    unsafe {
        CStr::from_ptr(ptr)
            .to_str()
            .map(|s| s.to_string())
            .map_err(|e| format!("Invalid UTF-8 sequence: {}", e))
    }
}

#[no_mangle]
pub extern "C" fn turso_create_synced_db(
    db_path: *const c_char,
    url: *const c_char,
    token: *const c_char,
) -> *mut c_char {
    let result = (|| {
        let db_path = ptr_to_string(db_path)?;
        let url = ptr_to_string(url)?;
        let token = ptr_to_string(token)?;

        let rt = &*RUNTIME;

        rt.block_on(async {
            match Builder::new_synced_database(&db_path, url, token).build().await {
                Ok(db) => {
                    let arc_db = Arc::new(db);
                    let mut connections = CONNECTIONS.lock().unwrap();
                    let connection_id = format!("conn_{}", connections.len());
                    connections.insert(connection_id.clone(), arc_db);
                    Ok(connection_id)
                }
                Err(e) => Err(format!("Failed to create database: {}", e)),
            }
        })
    })();

    result_to_json_ptr(result)
}

#[no_mangle]
pub extern "C" fn turso_sync(connection_id: *const c_char) -> *mut c_char {
    let result = (|| {
        let connection_id = ptr_to_string(connection_id)?;
        let rt = &*RUNTIME;

        rt.block_on(async {
            let connections = CONNECTIONS.lock().unwrap();
            match connections.get(&connection_id) {
                Some(db) => match db.sync().await {
                    Ok(_) => Ok("Sync successful".to_string()),
                    Err(e) => Err(format!("Sync failed: {}", e)),
                },
                None => Err("Connection not found".to_string()),
            }
        })
    })();
    result_to_json_ptr(result)
}

#[no_mangle]
pub extern "C" fn turso_query(
    connection_id: *const c_char,
    sql: *const c_char,
) -> *mut c_char {
    let result = (|| {
        let connection_id = ptr_to_string(connection_id)?;
        let sql = ptr_to_string(sql)?;

        let rt = &*RUNTIME;

        rt.block_on(async {
            let connections = CONNECTIONS.lock().unwrap();
            match connections.get(&connection_id) {
                Some(db) => match db.connect() {
                    Ok(conn) => execute_query_internal(&conn, &sql).await,
                    Err(e) => Err(format!("Connection failed: {}", e)),
                },
                None => Err("Connection not found".to_string()),
            }
        })
    })();
    result_to_json_ptr(result)
}

#[no_mangle]
pub extern "C" fn turso_execute(
    connection_id: *const c_char,
    sql: *const c_char,
) -> *mut c_char {
    let result = (|| {
        let connection_id = ptr_to_string(connection_id)?;
        let sql = ptr_to_string(sql)?;

        let rt = &*RUNTIME;

        rt.block_on(async {
            let connections = CONNECTIONS.lock().unwrap();
            match connections.get(&connection_id) {
                Some(db) => match db.connect() {
                    Ok(conn) => execute_statement_internal(&conn, &sql).await,
                    Err(e) => Err(format!("Connection failed: {}", e)),
                },
                None => Err("Connection not found".to_string()),
            }
        })
    })();
    result_to_json_ptr(result)
}

#[no_mangle]
pub extern "C" fn turso_execute_batch(
    connection_id: *const c_char,
    sql_statements_json: *const c_char,
) -> *mut c_char {
    let result = (|| {
        let connection_id = ptr_to_string(connection_id)?;
        let sql_statements_json = ptr_to_string(sql_statements_json)?;

        let sql_statements: Vec<String> = serde_json::from_str(&sql_statements_json)
            .map_err(|e| format!("JSON deserialization failed: {}", e))?;

        let rt = &*RUNTIME;

        rt.block_on(async {
            let connections = CONNECTIONS.lock().unwrap();
            match connections.get(&connection_id) {
                Some(db) => match db.connect() {
                    Ok(conn) => execute_batch_internal(&conn, &sql_statements).await,
                    Err(e) => Err(format!("Connection failed: {}", e)),
                },
                None => Err("Connection not found".to_string()),
            }
        })
    })();
    result_to_json_ptr(result)
}

#[no_mangle]
pub extern "C" fn turso_close_connection(connection_id: *const c_char) -> *mut c_char {
    let result = (|| {
        let connection_id = ptr_to_string(connection_id)?;
        let mut connections = CONNECTIONS.lock().unwrap();
        match connections.remove(&connection_id) {
            Some(_) => Ok("Connection closed".to_string()),
            None => Err("Connection not found".to_string()),
        }
    })();
    result_to_json_ptr(result)
}

#[no_mangle]
pub extern "C" fn turso_connection_count() -> i32 {
    CONNECTIONS.lock().unwrap().len() as i32
}

// --- Internal Helper Functions ---
async fn execute_query_internal(
    conn: &Connection,
    sql: &str,
) -> Result<Vec<Vec<String>>, String> {
    match conn.query(sql, ()).await {
        Ok(mut rows) => {
            let mut results = Vec::new();
            while let Some(row) = rows
                .next()
                .await
                .map_err(|e| format!("Row iteration error: {}", e))?
            {
                let mut row_data = Vec::new();
                let column_count = row.column_count();

                for i in 0..column_count {
                    let value = row
                        .get_value(i)
                        .map_err(|e| format!("Column access error: {}", e))?;
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
        Err(e) => Err(format!("Query failed: {}", e)),
    }
}

async fn execute_statement_internal(conn: &Connection, sql: &str) -> Result<i64, String> {
    conn.execute(sql, ())
        .await
        .map(|rows| rows as i64)
        .map_err(|e| format!("Execute failed: {}", e))
}

async fn execute_batch_internal(
    conn: &Connection,
    sql_statements: &[String],
) -> Result<i64, String> {
    if let Err(e) = conn.execute("BEGIN TRANSACTION", ()).await {
        return Err(format!("Failed to begin transaction: {}", e));
    }

    let mut total_affected = 0i64;

    for (i, sql) in sql_statements.iter().enumerate() {
        match conn.execute(sql, ()).await {
            Ok(affected) => total_affected += affected as i64,
            Err(e) => {
                let _ = conn.execute("ROLLBACK", ()).await;
                return Err(format!(
                    "Statement {} failed: {} (rolled back)",
                    i + 1,
                    e
                ));
            }
        }
    }

    match conn.execute("COMMIT", ()).await {
        Ok(_) => Ok(total_affected),
        Err(e) => {
            let _ = conn.execute("ROLLBACK", ()).await;
            Err(format!(
                "Failed to commit transaction: {} (rolled back)",
                e
            ))
        }
    }
}