// Package metrics holds the Prometheus collectors shared by the api and
// consumer binaries. Each is a separate process with its own default
// registry, so there's no cross-binary collision even though both import
// this package.
package metrics

import (
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	HTTPRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total HTTP requests processed, by method, route and status code.",
		},
		[]string{"method", "route", "status"},
	)

	HTTPRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request latency in seconds, by method and route.",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "route"},
	)

	DBUp = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "db_up",
			Help: "Whether the last database health check succeeded (1) or failed (0).",
		},
	)

	EventsPublishedTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "events_published_total",
			Help: "Total events the API attempted to publish, by event type and outcome.",
		},
		[]string{"event_type", "outcome"}, // outcome: success|error
	)

	EventsProcessedTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "events_processed_total",
			Help: "Total events the consumer processed, by event type and outcome.",
		},
		[]string{"event_type", "outcome"}, // outcome: success|duplicate|poison|error
	)

	EventProcessingDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "event_processing_duration_seconds",
			Help:    "Time to process a single event, by outcome.",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"outcome"},
	)
)

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

// Instrument wraps a handler registered under a fixed route pattern (e.g.
// "/api/accounts/{id}") so metrics use the low-cardinality pattern as a
// label instead of the raw, per-request URL path.
func Instrument(route string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

		next(rec, r)

		HTTPRequestsTotal.WithLabelValues(r.Method, route, strconv.Itoa(rec.status)).Inc()
		HTTPRequestDuration.WithLabelValues(r.Method, route).Observe(time.Since(start).Seconds())
	}
}
