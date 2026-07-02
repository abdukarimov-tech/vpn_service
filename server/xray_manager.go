package main

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"sync"
	"time"

	"golang.org/x/crypto/curve25519"
)

var (
	PrivateKey string
	PublicKey  string
	keysMu     sync.Mutex
)

// InitKeys initializes X25519 keys for REALITY
func InitKeys() error {
	keysMu.Lock()
	defer keysMu.Unlock()

	keyFile := "xray/keys.json"
	if _, err := os.Stat(keyFile); err == nil {
		data, err := os.ReadFile(keyFile)
		if err == nil {
			var keys struct {
				Private string `json:"private"`
				Public  string `json:"public"`
			}
			if json.Unmarshal(data, &keys) == nil {
				PrivateKey = keys.Private
				PublicKey = keys.Public
				log.Println("Loaded existing X25519 keys")
				return nil
			}
		}
	}

	// Generate private key
	privateKeyBytes := make([]byte, 32)
	if _, err := rand.Read(privateKeyBytes); err != nil {
		return fmt.Errorf("failed to generate private key: %w", err)
	}

	// Generate public key
	publicKeyBytes, err := curve25519.X25519(privateKeyBytes, curve25519.Basepoint)
	if err != nil {
		return fmt.Errorf("failed to generate public key: %w", err)
	}

	PrivateKey = base64.RawURLEncoding.EncodeToString(privateKeyBytes)
	PublicKey = base64.RawURLEncoding.EncodeToString(publicKeyBytes)

	keysData, _ := json.Marshal(map[string]string{
		"private": PrivateKey,
		"public":  PublicKey,
	})
	_ = os.WriteFile(keyFile, keysData, 0600)

	log.Println("Generated new X25519 keys for REALITY")
	return nil
}

// SyncXrayConfig updates config.json with current users from PostgreSQL and restarts Xray container
func SyncXrayConfig() error {
	templatePath := getEnv("XRAY_TEMPLATE_PATH", "xray/config.template.json")
	destPath := getEnv("XRAY_CONFIG_PATH", "xray/config.json")

	data, err := os.ReadFile(templatePath)
	if err != nil {
		return fmt.Errorf("failed to read template: %w", err)
	}

	var config map[string]interface{}
	if err := json.Unmarshal(data, &config); err != nil {
		return fmt.Errorf("failed to parse template JSON: %w", err)
	}

	// 1. Fetch users from DB
	rows, err := DB.Query("SELECT uuid FROM vpn_users")
	if err != nil {
		return fmt.Errorf("failed to query users: %w", err)
	}
	defer rows.Close()

	var clients []map[string]interface{}
	for rows.Next() {
		var u string
		if err := rows.Scan(&u); err != nil {
			return err
		}
		clients = append(clients, map[string]interface{}{
			"id":   u,
			"flow": "xtls-rprx-vision",
		})
	}

	// Prevent Xray startup error with empty clients
	if len(clients) == 0 {
		clients = append(clients, map[string]interface{}{
			"id":   "00000000-0000-0000-0000-000000000000",
			"flow": "xtls-rprx-vision",
		})
	}

	// 2. Insert clients and private key
	inbounds, ok := config["inbounds"].([]interface{})
	if !ok {
		return fmt.Errorf("inbounds not found in config")
	}

	for _, inboundRaw := range inbounds {
		inbound, ok := inboundRaw.(map[string]interface{})
		if !ok {
			continue
		}
		protocol, _ := inbound["protocol"].(string)
		if protocol == "vless" {
			// Set clients
			settings, ok := inbound["settings"].(map[string]interface{})
			if !ok {
				settings = make(map[string]interface{})
				inbound["settings"] = settings
			}
			settings["clients"] = clients

			// Set private key
			streamSettings, ok := inbound["streamSettings"].(map[string]interface{})
			if ok {
				realitySettings, ok := streamSettings["realitySettings"].(map[string]interface{})
				if ok {
					realitySettings["privateKey"] = PrivateKey
				}
			}
		}
	}

	// 3. Write to destination
	configData, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal config: %w", err)
	}

	err = os.WriteFile(destPath, configData, 0644)
	if err != nil {
		return fmt.Errorf("failed to write config file: %w", err)
	}

	log.Println("Wrote updated Xray config.json")

	// 4. Restart Xray container
	return restartXrayContainer()
}

func restartXrayContainer() error {
	containerName := getEnv("XRAY_CONTAINER_NAME", "xray")

	transport := &http.Transport{
		DialContext: func(_ context.Context, _, _ string) (net.Conn, error) {
			return net.Dial("unix", "/var/run/docker.sock")
		},
	}
	client := &http.Client{
		Transport: transport,
		Timeout:   10 * time.Second,
	}

	url := fmt.Sprintf("http://localhost/containers/%s/restart", containerName)
	resp, err := client.Post(url, "application/json", nil)
	if err != nil {
		log.Printf("Warning: failed to contact Docker socket to restart Xray: %v", err)
		return nil
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("failed to restart container, status: %d, body: %s", resp.StatusCode, string(body))
	}

	log.Printf("Successfully restarted Xray container '%s' via Docker API", containerName)
	return nil
}
