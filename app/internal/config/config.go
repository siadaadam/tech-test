// Package config loads runtime configuration from the environment so the
// same image behaves correctly across dev/staging/prod without a rebuild.
package config

import (
	"os"
	"strconv"
	"time"
)

// Config is a superset of everything either binary (api or consumer) needs.
// Each main only reads the fields relevant to it.
type Config struct {
	Port        string
	DatabaseURL string

	SQSQueueURL    string
	SQSDLQQueueURL string

	DBPingTimeout   time.Duration
	ShutdownDrain   time.Duration
	ShutdownTimeout time.Duration

	// EventPublishTimeout bounds how long the API waits for the best-effort
	// audit event publish before giving up and serving the response anyway.
	EventPublishTimeout time.Duration

	// ProcessTimeout bounds a single message's DB work in the consumer.
	ProcessTimeout time.Duration
}

func Load() Config {
	return Config{
		Port:        getEnv("PORT", "8080"),
		DatabaseURL: getEnv("DATABASE_URL", "postgres://banking:banking@localhost:5432/banking?sslmode=disable"),

		SQSQueueURL:    os.Getenv("SQS_QUEUE_URL"),
		SQSDLQQueueURL: os.Getenv("SQS_DLQ_QUEUE_URL"),

		DBPingTimeout:   getEnvDuration("DB_PING_TIMEOUT_SECONDS", 2*time.Second),
		ShutdownDrain:   getEnvDuration("SHUTDOWN_DRAIN_SECONDS", 5*time.Second),
		ShutdownTimeout: getEnvDuration("SHUTDOWN_TIMEOUT_SECONDS", 20*time.Second),

		EventPublishTimeout: getEnvDuration("EVENT_PUBLISH_TIMEOUT_SECONDS", 2*time.Second),
		ProcessTimeout:      getEnvDuration("PROCESS_TIMEOUT_SECONDS", 5*time.Second),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getEnvDuration(key string, fallback time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	seconds, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return time.Duration(seconds) * time.Second
}
