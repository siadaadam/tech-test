// Package httpapi holds the api binary's HTTP handlers.
package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"sync/atomic"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"banking-app/internal/dbstore"
	"banking-app/internal/events"
	"banking-app/internal/metrics"
)

// Publisher is the subset of the queue client the API needs. Kept as an
// interface so handler tests don't need a real SQS-compatible broker.
type Publisher interface {
	Publish(ctx context.Context, event events.Event) error
}

type API struct {
	DB             *pgxpool.Pool
	Publisher      Publisher
	Draining       *atomic.Bool
	PingTimeout    time.Duration
	PublishTimeout time.Duration
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

// Healthz is liveness: it reports whether the process itself is running and
// able to serve requests. It does not depend on Postgres, so a downstream
// database outage never causes Kubernetes to restart a perfectly healthy pod.
func Healthz(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// Readyz is readiness: it fails as soon as the process starts draining
// (SIGTERM received) and while Postgres is unreachable, so Kubernetes stops
// sending it new traffic in either case.
func (a *API) Readyz(w http.ResponseWriter, r *http.Request) {
	if a.Draining.Load() {
		writeError(w, http.StatusServiceUnavailable, "draining")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), a.PingTimeout)
	defer cancel()

	if err := a.DB.Ping(ctx); err != nil {
		metrics.DBUp.Set(0)
		writeError(w, http.StatusServiceUnavailable, "database unreachable")
		return
	}

	metrics.DBUp.Set(1)
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (a *API) GetAccount(w http.ResponseWriter, r *http.Request) {
	idParam := r.PathValue("id")
	id, err := strconv.ParseInt(idParam, 10, 64)
	if err != nil || id <= 0 {
		writeError(w, http.StatusBadRequest, "id must be a positive integer")
		return
	}

	account, err := dbstore.GetAccount(r.Context(), a.DB, id)
	if err != nil {
		if errors.Is(err, dbstore.ErrAccountNotFound) {
			writeError(w, http.StatusNotFound, "account not found")
			return
		}
		slog.Error("get account failed", "id", id, "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	writeJSON(w, http.StatusOK, account)

	a.publishAccountAccessed(id)
}

// publishAccountAccessed emits a best-effort audit event after a successful
// read. It never fails the request: the read already succeeded and was
// written to the response above, so a broker hiccup here is a gap in the
// audit trail, not a user-facing error. It's bounded by PublishTimeout so a
// slow/unreachable broker can't stall the handler goroutine indefinitely.
func (a *API) publishAccountAccessed(accountID int64) {
	if a.Publisher == nil {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), a.PublishTimeout)
	defer cancel()

	event := events.NewAccountAccessed(accountID)
	if err := a.Publisher.Publish(ctx, event); err != nil {
		metrics.EventsPublishedTotal.WithLabelValues(event.EventType, "error").Inc()
		slog.Error("publish account.accessed event failed", "account_id", accountID, "event_id", event.EventID, "error", err)
		return
	}
	metrics.EventsPublishedTotal.WithLabelValues(event.EventType, "success").Inc()
}
