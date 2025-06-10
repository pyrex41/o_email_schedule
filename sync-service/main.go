package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/tursodatabase/go-libsql"
)

type SyncService struct {
	connector *libsql.Connector
	db        *sql.DB
	dbPath    string
}

func NewSyncService(dbPath, primaryUrl, authToken string) (*SyncService, error) {
	// Create directory for the database if it doesn't exist
	if err := os.MkdirAll(filepath.Dir(dbPath), 0755); err != nil {
		return nil, fmt.Errorf("failed to create database directory: %w", err)
	}

	log.Printf("Creating embedded replica at: %s", dbPath)
	log.Printf("Syncing with: %s", primaryUrl)

	// Create embedded replica connector with periodic sync every 2 minutes
	connector, err := libsql.NewEmbeddedReplicaConnector(dbPath, primaryUrl,
		libsql.WithAuthToken(authToken),
		libsql.WithSyncInterval(2*time.Minute), // Auto-sync every 2 minutes
		libsql.WithReadYourWrites(true),        // Enable read-your-writes consistency
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create connector: %w", err)
	}

	db := sql.OpenDB(connector)
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	service := &SyncService{
		connector: connector,
		db:        db,
		dbPath:    dbPath,
	}

	// Perform initial sync
	log.Println("Performing initial sync...")
	if err := service.ManualSync(); err != nil {
		log.Printf("Initial sync failed (will retry): %v", err)
	} else {
		log.Println("Initial sync completed successfully")
	}

	return service, nil
}

func (s *SyncService) ManualSync() error {
	_, err := s.connector.Sync()
	return err
}

func (s *SyncService) Close() error {
	if s.db != nil {
		s.db.Close()
	}
	if s.connector != nil {
		return s.connector.Close()
	}
	return nil
}

func (s *SyncService) GetDBPath() string {
	return s.dbPath
}

// Health check endpoint
func (s *SyncService) healthHandler(w http.ResponseWriter, r *http.Request) {
	// Test database connection
	if err := s.db.Ping(); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprintf(w, "Database unavailable: %v", err)
		return
	}

	// Test that we can read from the database
	var count int
	err := s.db.QueryRow("SELECT COUNT(*) FROM organizations").Scan(&count)
	if err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprintf(w, "Database query failed: %v", err)
		return
	}

	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, "OK - Database path: %s, Organizations count: %d", s.dbPath, count)
}

// Manual sync endpoint
func (s *SyncService) syncHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		fmt.Fprintf(w, "Only POST method allowed")
		return
	}

	log.Println("Manual sync requested via API")
	if err := s.ManualSync(); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, "Sync failed: %v", err)
		return
	}

	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, "Sync completed successfully")
}

// Info endpoint to get database path
func (s *SyncService) infoHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"db_path": "%s", "status": "running"}`, s.dbPath)
}

func main() {
	// Get configuration from environment variables
	primaryUrl := os.Getenv("CENTRAL_DB_URL")
	authToken := os.Getenv("CENTRAL_DB_TOKEN")
	dbPath := os.Getenv("REPLICA_DB_PATH")
	port := os.Getenv("SYNC_SERVICE_PORT")

	// Set defaults
	if dbPath == "" {
		dbPath = "./data/central_replica.db"
	}
	if port == "" {
		port = "9191"
	}

	if primaryUrl == "" || authToken == "" {
		log.Fatal("CENTRAL_DB_URL and CENTRAL_DB_TOKEN environment variables are required")
	}

	log.Printf("Starting Turso sync service...")
	log.Printf("Primary URL: %s", primaryUrl)
	log.Printf("Replica path: %s", dbPath)
	log.Printf("Port: %s", port)

	// Create sync service
	service, err := NewSyncService(dbPath, primaryUrl, authToken)
	if err != nil {
		log.Fatalf("Failed to create sync service: %v", err)
	}
	defer service.Close()

	// Setup HTTP handlers
	http.HandleFunc("/health", service.healthHandler)
	http.HandleFunc("/sync", service.syncHandler)
	http.HandleFunc("/info", service.infoHandler)

	// Root handler with basic info
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, `Turso Sync Service
		
Available endpoints:
- GET  /health - Health check
- POST /sync   - Manual sync
- GET  /info   - Service info
		
Database replica path: %s
Auto-sync interval: 2 minutes
`, service.GetDBPath())
	})

	log.Printf("Sync service running on port %s", port)
	log.Printf("Database replica available at: %s", service.GetDBPath())
	log.Printf("Health check: http://localhost:%s/health", port)

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("HTTP server failed: %v", err)
	}
}
