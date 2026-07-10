package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"

	"banking-app/internal/config"
	"banking-app/internal/dbstore"
	"banking-app/internal/httpapi"
	"banking-app/internal/metrics"
	"banking-app/internal/queue"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	cfg := config.Load()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	pool, err := dbstore.Connect(ctx, cfg.DatabaseURL)
	cancel()
	if err != nil {
		slog.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	migrateCtx, migrateCancel := context.WithTimeout(context.Background(), 10*time.Second)
	if err := dbstore.MigrateAndSeed(migrateCtx, pool); err != nil {
		migrateCancel()
		slog.Error("failed to apply schema/seed data", "error", err)
		os.Exit(1)
	}
	migrateCancel()

	var publisher httpapi.Publisher
	if cfg.SQSQueueURL != "" {
		qCtx, qCancel := context.WithTimeout(context.Background(), 10*time.Second)
		qClient, err := queue.New(qCtx, cfg.SQSQueueURL, cfg.SQSDLQQueueURL)
		qCancel()
		if err != nil {
			slog.Error("failed to initialize queue client", "error", err)
			os.Exit(1)
		}
		publisher = qClient
	} else {
		slog.Warn("SQS_QUEUE_URL not set; account.accessed events will not be published")
	}

	var draining atomic.Bool
	api := &httpapi.API{
		DB:             pool,
		Publisher:      publisher,
		Draining:       &draining,
		PingTimeout:    cfg.DBPingTimeout,
		PublishTimeout: cfg.EventPublishTimeout,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", metrics.Instrument("/healthz", httpapi.Healthz))
	mux.HandleFunc("GET /readyz", metrics.Instrument("/readyz", api.Readyz))
	mux.Handle("GET /metrics", promhttp.Handler())
	mux.HandleFunc("GET /api/accounts/{id}", metrics.Instrument("/api/accounts/{id}", api.GetAccount))

	server := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	serverErr := make(chan error, 1)
	go func() {
		slog.Info("listening", "port", cfg.Port)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)

	select {
	case err := <-serverErr:
		slog.Error("server failed", "error", err)
		os.Exit(1)
	case sig := <-sigCh:
		slog.Info("shutdown signal received, draining", "signal", sig.String(), "drain_seconds", cfg.ShutdownDrain.Seconds())

		// Flip readiness first so Kubernetes stops routing new traffic here,
		// then wait out the drain window before actually closing anything -
		// this covers the propagation delay between the endpoint being
		// removed and kube-proxy/iptables catching up on every node.
		draining.Store(true)
		time.Sleep(cfg.ShutdownDrain)

		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
		defer shutdownCancel()

		slog.Info("shutting down http server")
		if err := server.Shutdown(shutdownCtx); err != nil {
			slog.Error("graceful shutdown failed, forcing close", "error", err)
			_ = server.Close()
		}
	}

	slog.Info("shutdown complete")
}
