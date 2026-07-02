package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"time"

	"golang.org/x/crypto/curve25519"
)

// Node agent: runs on every VPN node next to an Xray container.
// Responsibilities:
//  1. Ensure a persistent REALITY key pair (keys.json).
//  2. Self-register this node with the central API (name/ip/port/public key).
//  3. Periodically pull the full user UUID list and rewrite the local Xray
//     config, restarting Xray only when the client list actually changes.

type config struct {
	apiURL        string
	token         string
	nodeName      string
	nodeIP        string
	nodePort      int
	sni           string
	shortID       string
	xrayContainer string
	configPath    string
	templatePath  string
	keysPath      string
	interval      time.Duration
}

func loadConfig() config {
	port, _ := strconv.Atoi(getEnv("NODE_PORT", "8443"))
	interval, _ := strconv.Atoi(getEnv("SYNC_INTERVAL_SECONDS", "30"))
	return config{
		apiURL:        getEnv("API_URL", "http://vpn-api:8080"),
		token:         getEnv("NODE_AGENT_TOKEN", ""),
		nodeName:      getEnv("NODE_NAME", ""),
		nodeIP:        getEnv("NODE_IP", ""),
		nodePort:      port,
		sni:           getEnv("NODE_SNI", "images.apple.com"),
		shortID:       getEnv("NODE_SHORT_ID", "0123456789abcdef"),
		xrayContainer: getEnv("XRAY_CONTAINER_NAME", "xray"),
		configPath:    getEnv("XRAY_CONFIG_PATH", "/app/xray/config.json"),
		templatePath:  getEnv("XRAY_TEMPLATE_PATH", "/app/xray/config.template.json"),
		keysPath:      getEnv("XRAY_KEYS_PATH", "/app/xray/keys.json"),
		interval:      time.Duration(interval) * time.Second,
	}
}

func main() {
	log.Println("Starting VPN node agent...")
	cfg := loadConfig()

	if cfg.token == "" || cfg.nodeIP == "" {
		log.Fatal("NODE_AGENT_TOKEN and NODE_IP are required")
	}

	privateKey, publicKey, err := ensureKeys(cfg.keysPath)
	if err != nil {
		log.Fatalf("Key initialization failed: %v", err)
	}
	log.Printf("Node public key: %s", publicKey)

	// Self-register with retries until the control plane acknowledges.
	for {
		if err := registerNode(cfg, publicKey); err != nil {
			log.Printf("Node registration failed (retrying): %v", err)
			time.Sleep(10 * time.Second)
			continue
		}
		log.Println("Node registered with control plane")
		break
	}

	var lastHash string
	for {
		uuids, err := fetchClients(cfg)
		if err != nil {
			log.Printf("Failed to fetch clients: %v", err)
			time.Sleep(cfg.interval)
			continue
		}

		data, err := buildConfig(cfg, privateKey, uuids)
		if err != nil {
			log.Printf("Failed to build config: %v", err)
			time.Sleep(cfg.interval)
			continue
		}

		hash := hashBytes(data)
		if hash != lastHash {
			if err := os.WriteFile(cfg.configPath, data, 0644); err != nil {
				log.Printf("Failed to write config: %v", err)
				time.Sleep(cfg.interval)
				continue
			}
			log.Printf("Xray config updated (%d clients). Restarting Xray...", len(uuids))
			if err := restartXray(cfg.xrayContainer); err != nil {
				log.Printf("Failed to restart Xray: %v", err)
			}
			lastHash = hash
		}

		time.Sleep(cfg.interval)
	}
}

// ensureKeys loads an existing REALITY key pair or generates a new one.
func ensureKeys(path string) (private, public string, err error) {
	if data, readErr := os.ReadFile(path); readErr == nil {
		var keys struct {
			Private string `json:"private"`
			Public  string `json:"public"`
		}
		if json.Unmarshal(data, &keys) == nil && keys.Private != "" && keys.Public != "" {
			return keys.Private, keys.Public, nil
		}
	}

	privateKeyBytes := make([]byte, 32)
	if _, err = rand.Read(privateKeyBytes); err != nil {
		return "", "", fmt.Errorf("failed to generate private key: %w", err)
	}
	publicKeyBytes, err := curve25519.X25519(privateKeyBytes, curve25519.Basepoint)
	if err != nil {
		return "", "", fmt.Errorf("failed to generate public key: %w", err)
	}

	private = base64.RawURLEncoding.EncodeToString(privateKeyBytes)
	public = base64.RawURLEncoding.EncodeToString(publicKeyBytes)

	out, _ := json.Marshal(map[string]string{"private": private, "public": public})
	if err = os.WriteFile(path, out, 0600); err != nil {
		return "", "", fmt.Errorf("failed to persist keys: %w", err)
	}
	log.Println("Generated new REALITY key pair")
	return private, public, nil
}

func registerNode(cfg config, publicKey string) error {
	body, _ := json.Marshal(map[string]interface{}{
		"name":       cfg.nodeName,
		"ip":         cfg.nodeIP,
		"port":       cfg.nodePort,
		"public_key": publicKey,
		"short_id":   cfg.shortID,
		"sni":        cfg.sni,
	})

	req, err := http.NewRequest(http.MethodPost, cfg.apiURL+"/api/nodes/register", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+cfg.token)

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("status %d: %s", resp.StatusCode, string(b))
	}
	return nil
}

func fetchClients(cfg config) ([]string, error) {
	req, err := http.NewRequest(http.MethodGet, cfg.apiURL+"/api/nodes/clients", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+cfg.token)

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("status %d: %s", resp.StatusCode, string(b))
	}

	var out struct {
		UUIDs []string `json:"uuids"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	return out.UUIDs, nil
}

// buildConfig renders the Xray config from the template, injecting the clients,
// this node's private key, short id and SNI.
func buildConfig(cfg config, privateKey string, uuids []string) ([]byte, error) {
	raw, err := os.ReadFile(cfg.templatePath)
	if err != nil {
		return nil, fmt.Errorf("read template: %w", err)
	}

	var conf map[string]interface{}
	if err := json.Unmarshal(raw, &conf); err != nil {
		return nil, fmt.Errorf("parse template: %w", err)
	}

	clients := make([]map[string]interface{}, 0, len(uuids))
	for _, u := range uuids {
		clients = append(clients, map[string]interface{}{
			"id":   u,
			"flow": "xtls-rprx-vision",
		})
	}
	// Xray refuses to start with an empty client list.
	if len(clients) == 0 {
		clients = append(clients, map[string]interface{}{
			"id":   "00000000-0000-0000-0000-000000000000",
			"flow": "xtls-rprx-vision",
		})
	}

	inbounds, ok := conf["inbounds"].([]interface{})
	if !ok {
		return nil, fmt.Errorf("inbounds not found in template")
	}
	for _, ib := range inbounds {
		inbound, ok := ib.(map[string]interface{})
		if !ok {
			continue
		}
		if proto, _ := inbound["protocol"].(string); proto != "vless" {
			continue
		}
		settings, ok := inbound["settings"].(map[string]interface{})
		if !ok {
			settings = map[string]interface{}{}
			inbound["settings"] = settings
		}
		settings["clients"] = clients

		if stream, ok := inbound["streamSettings"].(map[string]interface{}); ok {
			if reality, ok := stream["realitySettings"].(map[string]interface{}); ok {
				reality["privateKey"] = privateKey
				reality["shortIds"] = []string{cfg.shortID}
				reality["serverNames"] = []string{cfg.sni}
				reality["dest"] = cfg.sni + ":443"
			}
		}
	}

	return json.MarshalIndent(conf, "", "  ")
}

func restartXray(containerName string) error {
	transport := &http.Transport{
		DialContext: func(_ context.Context, _, _ string) (net.Conn, error) {
			return net.Dial("unix", "/var/run/docker.sock")
		},
	}
	client := &http.Client{Transport: transport, Timeout: 15 * time.Second}

	url := fmt.Sprintf("http://localhost/containers/%s/restart", containerName)
	resp, err := client.Post(url, "application/json", nil)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("restart status %d: %s", resp.StatusCode, string(b))
	}
	log.Printf("Restarted Xray container '%s'", containerName)
	return nil
}

func hashBytes(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}
