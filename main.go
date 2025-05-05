package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type LogMessage struct {
	Message string `json:"message"`
}

var (
	logFilePath = "/app/logs/app.log"
	port        = getEnvOrDefault("APP_PORT", "8080")
	welcomeMsg  = getEnvOrDefault("WELCOME_MESSAGE", "Welcome to the custom app")
	logLevel    = getEnvOrDefault("LOG_LEVEL", "INFO")
)

var (
	logRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "app_log_requests_total",
			Help: "Total number of /log requests.",
		},
		[]string{"method"},
	)

	logAttemptsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "app_log_attempts_total",
			Help: "Total number of logging attempts (success/fail).",
		},
		[]string{"status"},
	)

	requestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name: "app_request_duration_seconds",
			Help: "Histogram of request duration.",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"path", "method"},
	)
)

func init() {
	prometheus.MustRegister(logRequestsTotal)
	prometheus.MustRegister(logAttemptsTotal)
	prometheus.MustRegister(requestDuration)
}

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

	http.HandleFunc("/", instrumentHandler("/", "GET", welcomeHandler))
	http.HandleFunc("/status", instrumentHandler("/status", "GET", statusHandler))
	http.HandleFunc("/log", instrumentHandler("/log", "POST", logHandler))
	http.HandleFunc("/logs", instrumentHandler("/logs", "GET", logsHandler))

	http.Handle("/metrics", promhttp.Handler())

	log.Printf("Starting server on port %s with log level %s", port, logLevel)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func instrumentHandler(path string, method string, handler http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		handler.ServeHTTP(w, r)
		duration := time.Since(start).Seconds()
		requestDuration.WithLabelValues(path, r.Method).Observe(duration)
	}
}

func welcomeHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprint(w, welcomeMsg)
}

func statusHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func logHandler(w http.ResponseWriter, r *http.Request) {
	logRequestsTotal.WithLabelValues(r.Method).Inc()

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var logMsg LogMessage
	if err := json.NewDecoder(r.Body).Decode(&logMsg); err != nil {
		logAttemptsTotal.WithLabelValues("fail").Inc()
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	f, err := os.OpenFile(logFilePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		logAttemptsTotal.WithLabelValues("fail").Inc()
		log.Printf("Error opening log file: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	defer f.Close()

	if _, err := f.WriteString(logMsg.Message + "\n"); err != nil {
		 logAttemptsTotal.WithLabelValues("fail").Inc()
		log.Printf("Error writing to log file: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	logAttemptsTotal.WithLabelValues("success").Inc()
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