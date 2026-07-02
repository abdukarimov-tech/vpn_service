package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"

	_ "github.com/lib/pq"
)

var DB *sql.DB

// Server represents a VPN node (one Xray instance on one machine).
type Server struct {
	ID        int    `json:"id"`
	Name      string `json:"name"`
	IP        string `json:"ip"`
	Port      int    `json:"port"`
	PublicKey string `json:"public_key"`
	ShortID   string `json:"short_id"`
	SNI       string `json:"sni"`
	Enabled   bool   `json:"enabled"`
	SortOrder int    `json:"sort_order"`
}

func InitDB() error {
	host := getEnv("DB_HOST", "localhost")
	port := getEnv("DB_PORT", "5432")
	user := getEnv("DB_USER", "postgres")
	password := getEnv("DB_PASSWORD", "postgres")
	dbname := getEnv("DB_NAME", "vpn_service")
	sslmode := getEnv("DB_SSLMODE", "disable")

	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		host, port, user, password, dbname, sslmode)

	var err error
	DB, err = sql.Open("postgres", connStr)
	if err != nil {
		return fmt.Errorf("error opening database: %w", err)
	}

	err = DB.Ping()
	if err != nil {
		return fmt.Errorf("error connecting to the database: %w", err)
	}

	log.Println("Successfully connected to database")

	if err = createTables(); err != nil {
		return fmt.Errorf("error creating tables: %w", err)
	}

	return nil
}

func createTables() error {
	usersQuery := `
	CREATE TABLE IF NOT EXISTS vpn_users (
		id SERIAL PRIMARY KEY,
		device_id VARCHAR(255) UNIQUE NOT NULL,
		uuid VARCHAR(36) UNIQUE NOT NULL,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		last_connected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);`

	serversQuery := `
	CREATE TABLE IF NOT EXISTS servers (
		id SERIAL PRIMARY KEY,
		name VARCHAR(100) NOT NULL,
		ip VARCHAR(64) NOT NULL,
		port INTEGER NOT NULL DEFAULT 8443,
		public_key VARCHAR(128) NOT NULL,
		short_id VARCHAR(32) NOT NULL DEFAULT '0123456789abcdef',
		sni VARCHAR(255) NOT NULL DEFAULT 'images.apple.com',
		enabled BOOLEAN NOT NULL DEFAULT TRUE,
		sort_order INTEGER NOT NULL DEFAULT 0,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		UNIQUE (ip, port)
	);`

	if _, err := DB.Exec(usersQuery); err != nil {
		return err
	}
	if _, err := DB.Exec(serversQuery); err != nil {
		return err
	}
	return nil
}

// GetEnabledServers returns all enabled VPN nodes ordered for display.
func GetEnabledServers() ([]Server, error) {
	rows, err := DB.Query(`
		SELECT id, name, ip, port, public_key, short_id, sni, enabled, sort_order
		FROM servers
		WHERE enabled = TRUE
		ORDER BY sort_order ASC, id ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var servers []Server
	for rows.Next() {
		var s Server
		if err := rows.Scan(&s.ID, &s.Name, &s.IP, &s.Port, &s.PublicKey, &s.ShortID, &s.SNI, &s.Enabled, &s.SortOrder); err != nil {
			return nil, err
		}
		servers = append(servers, s)
	}
	return servers, rows.Err()
}

// UpsertServer inserts or updates a node identified by (ip, port). Used by node
// agents to self-register their public key and connection details.
func UpsertServer(s Server) error {
	_, err := DB.Exec(`
		INSERT INTO servers (name, ip, port, public_key, short_id, sni, enabled, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, TRUE, CURRENT_TIMESTAMP)
		ON CONFLICT (ip, port) DO UPDATE SET
			name = EXCLUDED.name,
			public_key = EXCLUDED.public_key,
			short_id = EXCLUDED.short_id,
			sni = EXCLUDED.sni,
			enabled = TRUE,
			updated_at = CURRENT_TIMESTAMP`,
		s.Name, s.IP, s.Port, s.PublicKey, s.ShortID, s.SNI)
	return err
}

// GetAllUUIDs returns every registered user UUID (used by node agents to build
// their Xray client list).
func GetAllUUIDs() ([]string, error) {
	rows, err := DB.Query("SELECT uuid FROM vpn_users")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var uuids []string
	for rows.Next() {
		var u string
		if err := rows.Scan(&u); err != nil {
			return nil, err
		}
		uuids = append(uuids, u)
	}
	return uuids, rows.Err()
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}
