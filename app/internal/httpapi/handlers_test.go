package httpapi

import (
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestHealthzAlwaysOK(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	Healthz(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestReadyzFailsWhileDraining(t *testing.T) {
	var draining atomic.Bool
	draining.Store(true)

	// DB is intentionally nil: draining must short-circuit before any
	// database access, or this test would panic on a nil pointer dereference.
	a := &API{DB: nil, Draining: &draining, PingTimeout: time.Second}

	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	rec := httptest.NewRecorder()

	a.Readyz(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 while draining, got %d", rec.Code)
	}
}

func TestGetAccountRejectsNonNumericID(t *testing.T) {
	var draining atomic.Bool
	a := &API{DB: nil, Draining: &draining, PingTimeout: time.Second}

	req := httptest.NewRequest(http.MethodGet, "/api/accounts/not-a-number", nil)
	req.SetPathValue("id", "not-a-number")
	rec := httptest.NewRecorder()

	a.GetAccount(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for non-numeric id, got %d", rec.Code)
	}
}

func TestGetAccountRejectsNonPositiveID(t *testing.T) {
	var draining atomic.Bool
	a := &API{DB: nil, Draining: &draining, PingTimeout: time.Second}

	req := httptest.NewRequest(http.MethodGet, "/api/accounts/0", nil)
	req.SetPathValue("id", "0")
	rec := httptest.NewRecorder()

	a.GetAccount(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for non-positive id, got %d", rec.Code)
	}
}
