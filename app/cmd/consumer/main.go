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

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"banking-app/internal/config"
	"banking-app/internal/dbstore"
	"banking-app/internal/events"
	"banking-app/internal/metrics"
	"banking-app/internal/queue"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	cfg := config.Load()
	if cfg.SQSQueueURL == "" || cfg.SQSDLQQueueURL == "" {
		slog.Error("SQS_QUEUE_URL and SQS_DLQ_QUEUE_URL are both required for the consumer")
		os.Exit(1)
	}

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

	qCtx, qCancel := context.WithTimeout(context.Background(), 10*time.Second)
	q, err := queue.New(qCtx, cfg.SQSQueueURL, cfg.SQSDLQQueueURL)
	qCancel()
	if err != nil {
		slog.Error("failed to initialize queue client", "error", err)
		os.Exit(1)
	}

	var draining atomic.Bool
	server := newHealthServer(cfg.Port, pool, &draining, cfg.DBPingTimeout)

	serverErr := make(chan error, 1)
	go func() {
		slog.Info("consumer health server listening", "port", cfg.Port)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
	}()

	loopCtx, cancelLoop := context.WithCancel(context.Background())
	loopDone := make(chan struct{})
	go runConsumeLoop(loopCtx, q, pool, cfg.ProcessTimeout, loopDone)

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)

	select {
	case err := <-serverErr:
		slog.Error("health server failed", "error", err)
		os.Exit(1)
	case sig := <-sigCh:
		slog.Info("shutdown signal received", "signal", sig.String())

		// Stop reporting ready, then stop polling for new work; any
		// message already in hand keeps processing against its own
		// independent timeout (see runConsumeLoop) so in-flight work
		// always finishes instead of being abandoned mid-transaction.
		draining.Store(true)
		cancelLoop()

		select {
		case <-loopDone:
		case <-time.After(cfg.ShutdownTimeout):
			slog.Warn("consume loop did not stop within shutdown timeout")
		}

		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
		defer shutdownCancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			_ = server.Close()
		}
	}

	slog.Info("shutdown complete")
}

func newHealthServer(port string, pool *pgxpool.Pool, draining *atomic.Bool, pingTimeout time.Duration) *http.Server {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", metrics.Instrument("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	}))

	mux.HandleFunc("GET /readyz", metrics.Instrument("/readyz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if draining.Load() {
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"error":"draining"}`))
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), pingTimeout)
		defer cancel()

		if err := pool.Ping(ctx); err != nil {
			metrics.DBUp.Set(0)
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"error":"database unreachable"}`))
			return
		}

		metrics.DBUp.Set(1)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ready"}`))
	}))

	mux.Handle("GET /metrics", promhttp.Handler())

	return &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
}

func runConsumeLoop(loopCtx context.Context, q *queue.Client, pool *pgxpool.Pool, processTimeout time.Duration, done chan<- struct{}) {
	defer close(done)

	for {
		if loopCtx.Err() != nil {
			return
		}

		msgs, err := q.Receive(loopCtx)
		if err != nil {
			if loopCtx.Err() != nil {
				return
			}
			slog.Error("receive failed, backing off", "error", err)
			time.Sleep(2 * time.Second)
			continue
		}

		for _, m := range msgs {
			processOne(context.Background(), q, pool, m, processTimeout)
		}
	}
}

// processOne handles a single message with its own bounded timeout,
// independent of the poll loop's shutdown context, so a message already
// received always gets a chance to finish processing even after the
// consumer starts draining.
func processOne(parent context.Context, q *queue.Client, pool *pgxpool.Pool, msg types.Message, timeout time.Duration) {
	ctx, cancel := context.WithTimeout(parent, timeout)
	defer cancel()

	start := time.Now()
	body := aws.ToString(msg.Body)
	receiptHandle := aws.ToString(msg.ReceiptHandle)

	event, err := events.Unmarshal([]byte(body))
	if err == nil {
		err = event.Validate()
	}
	if err != nil {
		routePoison(ctx, q, body, receiptHandle, err)
		metrics.EventProcessingDuration.WithLabelValues("poison").Observe(time.Since(start).Seconds())
		return
	}

	inserted, err := dbstore.RecordAuditIfNew(ctx, pool, event.EventID, event.AccountID, event.EventType, event.OccurredAt)
	if err != nil {
		// Transient failure (e.g. a momentary DB outage): leave the message
		// alone. It becomes visible again once the visibility timeout
		// expires and SQS redelivers it; after max_receive_count attempts
		// the queue's redrive policy moves it to the DLQ automatically.
		metrics.EventsProcessedTotal.WithLabelValues(event.EventType, "error").Inc()
		metrics.EventProcessingDuration.WithLabelValues("error").Observe(time.Since(start).Seconds())
		slog.Error("failed to record audit, leaving message for retry", "event_id", event.EventID, "error", err)
		return
	}

	outcome := "duplicate"
	if inserted {
		outcome = "success"
	}
	metrics.EventsProcessedTotal.WithLabelValues(event.EventType, outcome).Inc()
	metrics.EventProcessingDuration.WithLabelValues(outcome).Observe(time.Since(start).Seconds())

	if err := q.Delete(ctx, receiptHandle); err != nil {
		slog.Error("failed to delete processed message", "event_id", event.EventID, "error", err)
		return
	}

	slog.Info("processed event", "event_id", event.EventID, "account_id", event.AccountID, "outcome", outcome)
}

// routePoison handles a message that can never succeed no matter how many
// times it's redelivered (bad JSON, missing fields, unknown event type).
// Rather than burning max_receive_count retries on something that will
// never parse, it's sent to the DLQ immediately and acked off the main
// queue. If the DLQ send itself fails, the message is left alone so the
// queue's redrive policy still catches it eventually as a backstop.
func routePoison(ctx context.Context, q *queue.Client, body, receiptHandle string, cause error) {
	slog.Warn("poison message, routing to DLQ", "error", cause)
	metrics.EventsProcessedTotal.WithLabelValues("unknown", "poison").Inc()

	if err := q.SendToDLQ(ctx, body, cause.Error()); err != nil {
		slog.Error("failed to send poison message to DLQ; leaving in queue for redrive policy backstop", "error", err)
		return
	}
	if err := q.Delete(ctx, receiptHandle); err != nil {
		slog.Error("failed to delete poison message after DLQ routing", "error", err)
	}
}
