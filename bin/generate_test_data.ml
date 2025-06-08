open Printf

(* Configuration for test data generation *)
let states = [|"CA"; "NY"; "TX"; "FL"; "IL"; "PA"; "OH"; "GA"; "NC"; "MI"; 
               "NJ"; "VA"; "WA"; "AZ"; "MA"; "TN"; "IN"; "MO"; "MD"; "WI";
               "CO"; "MN"; "SC"; "AL"; "LA"; "KY"; "OR"; "OK"; "CT"; "UT";
               "IA"; "NV"; "AR"; "MS"; "KS"; "NM"; "NE"; "WV"; "ID"; "HI";
               "NH"; "ME"; "MT"; "RI"; "DE"; "SD"; "ND"; "AK"; "VT"; "WY"|]

let carriers = [|"UnitedHealthcare"; "Anthem"; "Aetna"; "Cigna"; "Humana"; 
                 "Kaiser Permanente"; "Molina"; "Centene"; "Independence Blue Cross"|]

let plan_types = [|"HMO"; "PPO"; "EPO"; "POS"; "HDHP"|]

let first_names = [|"James"; "Mary"; "John"; "Patricia"; "Robert"; "Jennifer"; 
                    "Michael"; "Linda"; "William"; "Elizabeth"; "David"; "Barbara";
                    "Richard"; "Susan"; "Joseph"; "Jessica"; "Thomas"; "Sarah";
                    "Charles"; "Karen"; "Christopher"; "Lisa"; "Daniel"; "Nancy";
                    "Matthew"; "Betty"; "Anthony"; "Helen"; "Mark"; "Sandra"|]

let last_names = [|"Smith"; "Johnson"; "Williams"; "Brown"; "Jones"; "Garcia";
                   "Miller"; "Davis"; "Rodriguez"; "Martinez"; "Hernandez"; "Lopez";
                   "Gonzalez"; "Wilson"; "Anderson"; "Thomas"; "Taylor"; "Moore";
                   "Jackson"; "Martin"; "Lee"; "Perez"; "Thompson"; "White";
                   "Harris"; "Sanchez"; "Clark"; "Ramirez"; "Lewis"; "Robinson"|]

(* Random generators *)
let random_from_array arr = arr.(Random.int (Array.length arr))

let random_date_between start_year end_year =
  let year = start_year + Random.int (end_year - start_year + 1) in
  let month = 1 + Random.int 12 in
  let day = 1 + Random.int 28 in  (* Keep it simple, avoid Feb 29 issues *)
  Printf.sprintf "%04d-%02d-%02d" year month day

let random_email first last batch_start index =
  let providers = [|"gmail.com"; "yahoo.com"; "hotmail.com"; "aol.com"; "outlook.com"|] in
  let provider = random_from_array providers in
  let unique_id = batch_start + index in
  let timestamp = int_of_float (Unix.time ()) in
  Printf.sprintf "%s.%s.%d.%d@%s" 
    (String.lowercase_ascii first) 
    (String.lowercase_ascii last) 
    unique_id timestamp provider

let random_zip_code state =
  (* Generate realistic zip codes for states (simplified) *)
  match state with
  | "CA" -> Printf.sprintf "9%04d" (Random.int 10000)
  | "NY" -> Printf.sprintf "1%04d" (Random.int 10000)
  | "TX" -> Printf.sprintf "7%04d" (Random.int 10000)
  | "FL" -> Printf.sprintf "3%04d" (Random.int 10000)
  | _ -> Printf.sprintf "%05d" (10000 + Random.int 90000)

let random_phone () =
  Printf.sprintf "(%03d) %03d-%04d" 
    (200 + Random.int 800) 
    (200 + Random.int 800) 
    (Random.int 10000)

(* Create database schema *)
let create_schema db =
  (* Write schema to temporary file *)
  let temp_file = "/tmp/schema.sql" in
  let oc = open_out temp_file in
  output_string oc "CREATE TABLE IF NOT EXISTS contacts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    current_carrier TEXT NOT NULL,
    plan_type TEXT NOT NULL,
    effective_date TEXT NOT NULL,
    birth_date TEXT NOT NULL,
    tobacco_user INTEGER NOT NULL,
    gender TEXT NOT NULL,
    state TEXT NOT NULL,
    zip_code TEXT NOT NULL,
    agent_id INTEGER,
    last_emailed DATETIME,
    phone_number TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'active',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS email_schedules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    contact_id INTEGER NOT NULL,
    email_type TEXT NOT NULL,
    scheduled_send_date TEXT NOT NULL,
    scheduled_send_time TEXT NOT NULL DEFAULT '08:30:00',
    status TEXT NOT NULL DEFAULT 'scheduled',
    skip_reason TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    batch_id TEXT,
    event_year INTEGER,
    event_month INTEGER,
    event_day INTEGER,
    catchup_note TEXT,
    sent_at TEXT,
    sendgrid_message_id TEXT,
    sms_sent_at TEXT,
    twilio_sms_id TEXT,
    actual_send_datetime TEXT,
    priority INTEGER DEFAULT 10,
    campaign_instance_id INTEGER,
    email_template TEXT,
    sms_template TEXT,
    scheduler_run_id TEXT,
    metadata TEXT,
    FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE CASCADE
  );

  CREATE INDEX IF NOT EXISTS idx_contacts_birth_date ON contacts(birth_date);
  CREATE INDEX IF NOT EXISTS idx_contacts_effective_date ON contacts(effective_date);
  CREATE INDEX IF NOT EXISTS idx_contacts_state ON contacts(state);
  CREATE INDEX IF NOT EXISTS idx_email_schedules_date_time_status ON email_schedules(scheduled_send_date, scheduled_send_time, status);
  CREATE UNIQUE INDEX IF NOT EXISTS idx_email_schedules_unique ON email_schedules(contact_id, email_type, scheduled_send_date);
  CREATE INDEX IF NOT EXISTS idx_email_schedules_org_contact ON email_schedules(contact_id);
  CREATE INDEX IF NOT EXISTS idx_email_schedules_org_send_date ON email_schedules(scheduled_send_date);
  CREATE INDEX IF NOT EXISTS idx_email_schedules_status ON email_schedules(status);
  CREATE UNIQUE INDEX IF NOT EXISTS idx_email_schedules_unique_event ON email_schedules(contact_id, email_type, event_year);
  CREATE INDEX IF NOT EXISTS idx_email_schedules_event_date ON email_schedules(event_year, event_month, event_day);
  CREATE INDEX IF NOT EXISTS idx_schedules_lookup ON email_schedules(contact_id, email_type, scheduled_send_date);
  CREATE INDEX IF NOT EXISTS idx_schedules_status_date ON email_schedules(status, scheduled_send_date);
  CREATE INDEX IF NOT EXISTS idx_schedules_run_id ON email_schedules(scheduler_run_id);
  
  CREATE TRIGGER IF NOT EXISTS update_email_schedules_updated_at
  AFTER UPDATE ON email_schedules
  FOR EACH ROW
  BEGIN
      UPDATE email_schedules
      SET updated_at = CURRENT_TIMESTAMP
      WHERE id = OLD.id;
  END;
  ";
  close_out oc;
  
  let cmd = Printf.sprintf "sqlite3 %s < %s" db temp_file in
  let exit_code = Sys.command cmd in
  let _ = Sys.command ("rm " ^ temp_file) in
  if exit_code <> 0 then
    failwith ("Failed to create schema in " ^ db)

(* Helper function to convert contact data to string array for prepared statement *)
let contact_to_values first_name last_name email carrier plan_type effective_date birth_date tobacco_user gender state zip_code agent_id phone =
  [|
    first_name; last_name; email; carrier; plan_type; effective_date; birth_date;
    string_of_int tobacco_user; gender; state; zip_code; string_of_int agent_id; phone; "active"
  |]

(* Fixed batch generation using prepared statements instead of huge SQL strings *)
let generate_contacts_batch_fixed db start_id count =
  printf "Generating contacts batch %d-%d using prepared statements...\n%!" start_id (start_id + count - 1);
  
  (* Set database path for the Database module *)
  Scheduler.Db.Database_native.set_db_path db;
  
  (* Prepare contact data *)
  let contacts_data = ref [] in
  
  for i = 0 to count - 1 do
    let first_name = random_from_array first_names in
    let last_name = random_from_array last_names in
    let email = random_email first_name last_name start_id i in
    let carrier = random_from_array carriers in
    let plan_type = random_from_array plan_types in
    let state = random_from_array states in
    let zip_code = random_zip_code state in
    let phone = random_phone () in
    let birth_date = random_date_between 1940 2005 in
    let effective_date = random_date_between 2020 2024 in
    let tobacco_user = Random.int 2 in
    let gender = if Random.bool () then "M" else "F" in
    let agent_id = 1 + Random.int 50 in
    
    let values = contact_to_values first_name last_name email carrier plan_type 
                   effective_date birth_date tobacco_user gender state zip_code agent_id phone in
    contacts_data := values :: !contacts_data;
  done;
  
  (* Use the existing batch_insert_with_prepared_statement function *)
  let insert_sql = "INSERT INTO contacts (first_name, last_name, email, current_carrier, plan_type, effective_date, birth_date, tobacco_user, gender, state, zip_code, agent_id, phone_number, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)" in
  
  match Scheduler.Db.Database_native.batch_insert_with_prepared_statement insert_sql (List.rev !contacts_data) with
  | Ok inserted_count ->
      printf "✅ Successfully inserted %d contacts\n%!" inserted_count
  | Error err ->
      failwith ("Failed to insert contacts batch: " ^ Scheduler.Db.Database_native.string_of_db_error err)

(* Generate batch of contacts - keeping the old version for fallback *)
let generate_contacts_batch db start_id count =
  printf "Generating contacts batch %d-%d...\n%!" start_id (start_id + count - 1);
  
  let contacts = Buffer.create (count * 200) in
  Buffer.add_string contacts "BEGIN TRANSACTION;\n";
  
  for i = 0 to count - 1 do
    let first_name = random_from_array first_names in
    let last_name = random_from_array last_names in
    let email = random_email first_name last_name start_id i in
    let carrier = random_from_array carriers in
    let plan_type = random_from_array plan_types in
    let state = random_from_array states in
    let zip_code = random_zip_code state in
    let phone = random_phone () in
    let birth_date = random_date_between 1940 2005 in
    let effective_date = random_date_between 2020 2024 in
    let tobacco_user = Random.int 2 in
    let gender = if Random.bool () then "M" else "F" in
    let agent_id = 1 + Random.int 50 in
    
    let sql = Printf.sprintf 
      "INSERT INTO contacts (first_name, last_name, email, current_carrier, plan_type, effective_date, birth_date, tobacco_user, gender, state, zip_code, agent_id, phone_number, status) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%s', %d, '%s', '%s', '%s', %d, '%s', 'active');\n"
      (String.escaped first_name) (String.escaped last_name) (String.escaped email)
      (String.escaped carrier) (String.escaped plan_type) effective_date birth_date
      tobacco_user gender state zip_code agent_id phone in
    
    Buffer.add_string contacts sql;
  done;
  
  Buffer.add_string contacts "COMMIT;\n";
  
  (* Write to temporary file and execute *)
  let temp_file = Printf.sprintf "/tmp/contacts_batch_%d.sql" start_id in
  let oc = open_out temp_file in
  output_string oc (Buffer.contents contacts);
  close_out oc;
  
  let cmd = Printf.sprintf "sqlite3 %s < %s" db temp_file in
  let exit_code = Sys.command cmd in
  let _ = Sys.command ("rm " ^ temp_file) in
  
  if exit_code <> 0 then
    failwith ("Failed to insert contacts batch starting at " ^ string_of_int start_id)

(* Generate large dataset with fixed batch insertion *)
let generate_dataset db_name total_contacts batch_size use_prepared_statements =
  printf "🚀 Generating %d contacts in database: %s\n" total_contacts db_name;
  printf "Using batch size: %d contacts per batch\n" batch_size;
  printf "Method: %s\n\n" (if use_prepared_statements then "Prepared statements (FIXED)" else "SQL strings (legacy)");
  
  (* Initialize random seed *)
  Random.self_init ();
  
  (* Remove existing database *)
  if Sys.file_exists db_name then
    Sys.remove db_name;
  
  (* Create schema *)
  printf "📋 Creating database schema...\n";
  create_schema db_name;
  
  (* Generate contacts in batches *)
  let batches = (total_contacts + batch_size - 1) / batch_size in
  printf "📊 Generating %d batches of contacts...\n\n" batches;
  
  let start_time = Unix.time () in
  
  for batch = 0 to batches - 1 do
    let start_id = batch * batch_size + 1 in
    let remaining = total_contacts - batch * batch_size in
    let current_batch_size = min batch_size remaining in
    
    if current_batch_size > 0 then (
      let batch_start = Unix.time () in
      
      (* Use the new fixed method or fall back to legacy *)
      if use_prepared_statements then
        generate_contacts_batch_fixed db_name start_id current_batch_size
      else
        generate_contacts_batch db_name start_id current_batch_size;
        
      let batch_time = Unix.time () -. batch_start in
      
      printf "   Batch %d/%d completed in %.2f seconds (%.0f contacts/second)\n%!" 
        (batch + 1) batches batch_time (float_of_int current_batch_size /. batch_time);
    )
  done;
  
  let total_time = Unix.time () -. start_time in
  
  printf "\n✅ Database generation complete!\n";
  printf "📈 Performance Summary:\n";
  printf "   • Total contacts: %d\n" total_contacts;
  printf "   • Generation time: %.2f seconds\n" total_time;
  printf "   • Average throughput: %.0f contacts/second\n" (float_of_int total_contacts /. total_time);
  
  (* Verify the database *)
  printf "\n🔍 Verifying database...\n";
  let cmd = Printf.sprintf "sqlite3 %s \"SELECT COUNT(*) FROM contacts;\"" db_name in
  let exit_code = Sys.command cmd in
  if exit_code = 0 then
    printf "✅ Database verification successful!\n"
  else
    printf "❌ Database verification failed!\n"

(* Generate realistic distribution based on golden dataset *)
let analyze_golden_dataset () =
  if not (Sys.file_exists "golden_dataset.sqlite3") then (
    printf "❌ golden_dataset.sqlite3 not found\n";
    exit 1
  );
  
  printf "📊 Analyzing golden dataset for realistic patterns...\n\n";
  
  (* Analyze state distribution *)
  let cmd = "sqlite3 golden_dataset.sqlite3 \"SELECT state, COUNT(*) as count FROM contacts GROUP BY state ORDER BY count DESC LIMIT 10;\"" in
  printf "🗺️  Top 10 states by contact count:\n";
  let _ = Sys.command cmd in
  
  (* Analyze birth date distribution *)
  printf "\n📅 Birth date year distribution:\n";
  let cmd2 = "sqlite3 golden_dataset.sqlite3 \"SELECT substr(birth_date, 1, 4) as year, COUNT(*) as count FROM contacts GROUP BY year ORDER BY count DESC LIMIT 10;\"" in
  let _ = Sys.command cmd2 in
  
  (* Analyze effective date distribution *)
  printf "\n📋 Effective date distribution:\n";
  let cmd3 = "sqlite3 golden_dataset.sqlite3 \"SELECT substr(effective_date, 1, 7) as month, COUNT(*) as count FROM contacts GROUP BY month ORDER BY month DESC LIMIT 10;\"" in
  let _ = Sys.command cmd3 in
  
  printf "\n✅ Golden dataset analysis complete!\n"

let main () =
  let argc = Array.length Sys.argv in
  if argc < 2 then (
    printf "Usage: %s <command> [args]\n" Sys.argv.(0);
    printf "Commands:\n";
    printf "  generate <db_name> <count> [batch_size] [--use-prepared]  - Generate test database\n";
    printf "  analyze                                                   - Analyze golden dataset patterns\n";
    printf "\nExamples:\n";
    printf "  %s generate large_test_dataset.sqlite3 25000 1000 --use-prepared\n" Sys.argv.(0);
    printf "  %s generate huge_test_dataset.sqlite3 100000 2000\n" Sys.argv.(0);
    printf "  %s analyze\n" Sys.argv.(0);
    exit 1
  );
  
  let command = Sys.argv.(1) in
  match command with
  | "generate" when argc >= 4 ->
      let db_name = Sys.argv.(2) in
      let count = int_of_string Sys.argv.(3) in
      let batch_size = if argc >= 5 then int_of_string Sys.argv.(4) else 1000 in
      let use_prepared = 
        argc >= 6 && Sys.argv.(5) = "--use-prepared" ||
        argc >= 7 && Sys.argv.(6) = "--use-prepared"
      in
      generate_dataset db_name count batch_size use_prepared
  | "analyze" ->
      analyze_golden_dataset ()
  | _ ->
      printf "Invalid command or arguments\n";
      exit 1

(* Entry point *)
let () = main () 