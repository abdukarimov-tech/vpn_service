package main

import (
	"crypto/rand"
	"encoding/json"
	"log"
	"net/http"
	"os"
)

type RegisterRequest struct {
	DeviceID string `json:"device_id"`
}

type RegisterResponse struct {
	UUID    string       `json:"uuid"`
	Servers []ServerInfo `json:"servers"`
}

type ServerInfo struct {
	Name string `json:"name"`
	IP   string `json:"ip"`
	Port string `json:"port"`
	Link string `json:"link"`
}

type ConnectRequest struct {
	DeviceID string `json:"device_id"`
}

func main() {
	log.Println("Starting VPN API Server...")

	// Ensure xray directory exists
	if err := os.MkdirAll("xray", 0755); err != nil {
		log.Fatalf("Error creating xray directory: %v", err)
	}

	// Initialize Database
	if err := InitDB(); err != nil {
		log.Fatalf("Database initialization failed: %v", err)
	}
	defer DB.Close()

	// Initialize X25519 Keys
	if err := InitKeys(); err != nil {
		log.Fatalf("Key initialization failed: %v", err)
	}

	// Sync initial config
	if err := SyncXrayConfig(); err != nil {
		log.Printf("Warning: initial config sync failed: %v", err)
	}

	// Setup Routes
	http.HandleFunc("/api/register", handleRegister)
	http.HandleFunc("/api/connect", handleConnect)
	http.HandleFunc("/api/health", handleHealth)

	// Start Server
	port := getEnv("PORT", "8080")
	log.Printf("Server running on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req RegisterRequest
	err := json.NewDecoder(r.Body).Decode(&req)
	if err != nil || req.DeviceID == "" {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	var userUUID string
	// Check if user already exists in PostgreSQL
	err = DB.QueryRow("SELECT uuid FROM vpn_users WHERE device_id = $1", req.DeviceID).Scan(&userUUID)
	if err != nil {
		// User does not exist, create new
		// Generate UUID using crypto/rand in a helper or standard package
		userUUID = generateRandomUUID()
		_, err = DB.Exec("INSERT INTO vpn_users (device_id, uuid) VALUES ($1, $2)", req.DeviceID, userUUID)
		if err != nil {
			log.Printf("Error registering user: %v", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}
		log.Printf("Registered new user: device=%s, uuid=%s", req.DeviceID, userUUID)

		// Sync configuration and restart Xray container asynchronously
		go func() {
			if err := SyncXrayConfig(); err != nil {
				log.Printf("Error syncing Xray configuration: %v", err)
			}
		}()
	} else {
		log.Printf("Existing user requested registration: device=%s, uuid=%s", req.DeviceID, userUUID)
	}

	serverIP := getEnv("VPN_SERVER_IP", "127.0.0.1")
	serverPort := getEnv("VPN_SERVER_PORT", "8443")
	serverName := getEnv("VPN_SERVER_NAME", "Primary Server")

	link := getVLESSLink(userUUID, serverIP, serverPort, PublicKey, serverName)

	resp := RegisterResponse{
		UUID: userUUID,
		Servers: []ServerInfo{
			{
				Name: serverName,
				IP:   serverIP,
				Port: serverPort,
				Link: link,
			},
		},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func handleConnect(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req ConnectRequest
	err := json.NewDecoder(r.Body).Decode(&req)
	if err != nil || req.DeviceID == "" {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	_, err = DB.Exec("UPDATE vpn_users SET last_connected_at = CURRENT_TIMESTAMP WHERE device_id = $1", req.DeviceID)
	if err != nil {
		log.Printf("Error logging connection for device %s: %v", req.DeviceID, err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok"}`))
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"healthy"}`))
}

func getVLESSLink(userUUID, ip, port, publicKey, serverName string) string {
	return "vless://" + userUUID + "@" + ip + ":" + port +
		"?security=reality&sni=images.apple.com&fp=chrome&pbk=" + publicKey +
		"&sid=0123456789abcdef&flow=xtls-rprx-vision&type=tcp#" + serverName
}

// Simple RFC 4122 compliant UUID generator using crypto/rand
func generateRandomUUID() string {
	uuid := make([]byte, 16)
	_, _ = rand.Read(uuid)
	// Set version 4 (random)
	uuid[6] = (uuid[6] & 0x0f) | 0x40
	// Set variant (RFC 4122)
	uuid[8] = (uuid[8] & 0x3f) | 0x80
	return formatUUID(uuid)
}

func formatUUID(b []byte) string {
	return string(encodeHex(b[0:4])) + "-" +
		string(encodeHex(b[4:6])) + "-" +
		string(encodeHex(b[6:8])) + "-" +
		string(encodeHex(b[8:10])) + "-" +
		string(encodeHex(b[10:16]))
}

func encodeHex(dst []byte) []byte {
	const hextable = "0123456789abcdef"
	res := make([]byte, len(dst)*2)
	for i, v := range dst {
		res[i*2] = hextable[v>>4]
		res[i*2+1] = hextable[v&0x0f]
	}
	return res
}
