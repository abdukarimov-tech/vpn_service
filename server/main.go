package main

import (
	"crypto/rand"
	"encoding/json"
	"log"
	"net/http"
	"net/url"
	"strconv"
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

// NodeRegisterRequest is sent by a node agent to register/update itself.
type NodeRegisterRequest struct {
	Name      string `json:"name"`
	IP        string `json:"ip"`
	Port      int    `json:"port"`
	PublicKey string `json:"public_key"`
	ShortID   string `json:"short_id"`
	SNI       string `json:"sni"`
}

func main() {
	log.Println("Starting VPN API Server (control plane)...")

	if err := InitDB(); err != nil {
		log.Fatalf("Database initialization failed: %v", err)
	}
	defer DB.Close()

	// Client-facing endpoints
	http.HandleFunc("/api/register", handleRegister)
	http.HandleFunc("/api/connect", handleConnect)
	http.HandleFunc("/api/health", handleHealth)

	// Node-agent endpoints (token protected)
	http.HandleFunc("/api/nodes/register", handleNodeRegister)
	http.HandleFunc("/api/nodes/clients", handleNodeClients)

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
	err = DB.QueryRow("SELECT uuid FROM vpn_users WHERE device_id = $1", req.DeviceID).Scan(&userUUID)
	if err != nil {
		userUUID = generateRandomUUID()
		_, err = DB.Exec("INSERT INTO vpn_users (device_id, uuid) VALUES ($1, $2)", req.DeviceID, userUUID)
		if err != nil {
			log.Printf("Error registering user: %v", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}
		log.Printf("Registered new user: device=%s, uuid=%s", req.DeviceID, userUUID)
	} else {
		log.Printf("Existing user requested registration: device=%s", req.DeviceID)
	}

	servers, err := GetEnabledServers()
	if err != nil {
		log.Printf("Error fetching servers: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	var serverInfos []ServerInfo
	for _, s := range servers {
		portStr := strconv.Itoa(s.Port)
		link := getVLESSLink(userUUID, s)
		serverInfos = append(serverInfos, ServerInfo{
			Name: s.Name,
			IP:   s.IP,
			Port: portStr,
			Link: link,
		})
	}

	resp := RegisterResponse{
		UUID:    userUUID,
		Servers: serverInfos,
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

// handleNodeRegister lets a node agent register or update its details.
func handleNodeRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !authorizeNode(r) {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req NodeRegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.IP == "" || req.PublicKey == "" {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	if req.Port == 0 {
		req.Port = 8443
	}
	if req.ShortID == "" {
		req.ShortID = "0123456789abcdef"
	}
	if req.SNI == "" {
		req.SNI = "images.apple.com"
	}
	if req.Name == "" {
		req.Name = req.IP
	}

	err := UpsertServer(Server{
		Name:      req.Name,
		IP:        req.IP,
		Port:      req.Port,
		PublicKey: req.PublicKey,
		ShortID:   req.ShortID,
		SNI:       req.SNI,
	})
	if err != nil {
		log.Printf("Error upserting server %s: %v", req.IP, err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	log.Printf("Node registered/updated: %s (%s:%d)", req.Name, req.IP, req.Port)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok"}`))
}

// handleNodeClients returns all user UUIDs for node agents to sync their Xray config.
func handleNodeClients(w http.ResponseWriter, r *http.Request) {
	if !authorizeNode(r) {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	uuids, err := GetAllUUIDs()
	if err != nil {
		log.Printf("Error fetching UUIDs: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string][]string{"uuids": uuids})
}

func authorizeNode(r *http.Request) bool {
	expected := getEnv("NODE_AGENT_TOKEN", "")
	if expected == "" {
		// If no token configured, deny node endpoints for safety.
		return false
	}
	return r.Header.Get("Authorization") == "Bearer "+expected
}

func getVLESSLink(userUUID string, s Server) string {
	portStr := strconv.Itoa(s.Port)
	return "vless://" + userUUID + "@" + s.IP + ":" + portStr +
		"?security=reality&sni=" + url.QueryEscape(s.SNI) +
		"&fp=chrome&pbk=" + s.PublicKey +
		"&sid=" + url.QueryEscape(s.ShortID) +
		"&flow=xtls-rprx-vision&type=tcp#" + url.QueryEscape(s.Name)
}

// Simple RFC 4122 compliant UUID generator using crypto/rand
func generateRandomUUID() string {
	uuid := make([]byte, 16)
	_, _ = rand.Read(uuid)
	uuid[6] = (uuid[6] & 0x0f) | 0x40
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
