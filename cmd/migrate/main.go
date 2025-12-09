package main

import (
	"log"
	"os"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

func main() {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL env var is required")
	}

	m, err := migrate.New(
		"file://migrations",
		dbURL,
	)
	if err != nil {
		log.Fatalf("migrate.New error: %v", err)
	}

	log.Println("Running migrations...")
	if err := m.Up(); err != nil && err != migrate.ErrNoChange {
		log.Fatalf("Migration failed: %v", err)
	}

	log.Println("Migrations completed successfully.")
}
