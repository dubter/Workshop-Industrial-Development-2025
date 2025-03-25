package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
)

type LogMessage struct {
	Message string `json:"message"`
}

var (
	logFilePath  = "/app/logs/app.log"
	port         = getEnvOrDefault("APP_PORT", "8080")
	welcomeMsg   = getEnvOrDefault("WELCOME_MESSAGE", "Welcome to the custom app")
	logLevel     = getEnvOrDefault("LOG_LEVEL", "INFO")
)

func getEnvOrDefault(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}

func main() {
	logDir := filepath.Dir(logFilePath)
	if err := os.MkdirAll(logDir, 0755); err != nil {
		log.Fatalf("Failed to create log directory: %v", err)
	}

	http.HandleFunc("/", welcomeHandler)
	http.HandleFunc("/status", statusHandler)
	http.HandleFunc("/log", logHandler)
	http.HandleFunc("/logs", logsHandler)

	log.Printf("Starting server on port %s with log level %s", port, logLevel)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func welcomeHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprint(w, welcomeMsg)
}

func statusHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func logHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var logMsg LogMessage
	if err := json.NewDecoder(r.Body).Decode(&logMsg); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	f, err := os.OpenFile(logFilePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Printf("Error opening log file: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	defer f.Close()

	if _, err := f.WriteString(logMsg.Message + "\n"); err != nil {
		log.Printf("Error writing to log file: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{"status": "log created"})
}

func logsHandler(w http.ResponseWriter, r *http.Request) {
	content, err := os.ReadFile(logFilePath)
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Fprint(w, "")
			return
		}
		log.Printf("Error reading log file: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	fmt.Fprint(w, string(content))
}
