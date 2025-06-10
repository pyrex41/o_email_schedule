#!/bin/bash

# Load environment variables from parent directory
if [ -f "../.env" ]; then
    export $(cat ../.env | grep -v '^#' | xargs)
fi

# Set default values if not provided
export REPLICA_DB_PATH="${REPLICA_DB_PATH:-./data/central_replica.db}"
export SYNC_SERVICE_PORT="${SYNC_SERVICE_PORT:-9191}"

echo "Starting Turso Sync Service..."
echo "Central DB: $CENTRAL_DB_URL"
echo "Replica Path: $REPLICA_DB_PATH"
echo "Port: $SYNC_SERVICE_PORT"

# Initialize Go module and download dependencies
go mod tidy

# Run the service
go run main.go 