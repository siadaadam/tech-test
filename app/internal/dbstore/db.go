// Package dbstore is the only part of the app that talks to Postgres.
package dbstore

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const schema = `
CREATE TABLE IF NOT EXISTS accounts (
	id            BIGSERIAL PRIMARY KEY,
	owner_name    TEXT NOT NULL,
	balance_cents BIGINT NOT NULL DEFAULT 0,
	currency      TEXT NOT NULL DEFAULT 'USD',
	created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- processed_events is the idempotency ledger: one row per event_id, ever.
-- The consumer inserts into this table and into audit_log in the same
-- transaction, so "have we handled this event" and "did we record its
-- effect" can never disagree.
CREATE TABLE IF NOT EXISTS processed_events (
	event_id     TEXT PRIMARY KEY,
	processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit_log (
	id          BIGSERIAL PRIMARY KEY,
	event_id    TEXT NOT NULL REFERENCES processed_events(event_id),
	account_id  BIGINT NOT NULL,
	event_type  TEXT NOT NULL,
	occurred_at TIMESTAMPTZ NOT NULL,
	recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
`

// seedData is inserted once so a freshly created database has something for
// GET /api/accounts/{id} to return without any manual setup.
const seedData = `
INSERT INTO accounts (id, owner_name, balance_cents, currency)
VALUES
	(1, 'Ada Lovelace', 523147, 'USD'),
	(2, 'Alan Turing', 1099999, 'GBP'),
	(3, 'Grace Hopper', 42000, 'USD')
ON CONFLICT (id) DO NOTHING;
`

func Connect(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) {
	poolCfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("parsing DATABASE_URL: %w", err)
	}
	poolCfg.MaxConnLifetime = 30 * time.Minute
	poolCfg.HealthCheckPeriod = 30 * time.Second

	pool, err := pgxpool.NewWithConfig(ctx, poolCfg)
	if err != nil {
		return nil, fmt.Errorf("creating connection pool: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("pinging database: %w", err)
	}

	return pool, nil
}

// migrationLockKey is an arbitrary, fixed advisory lock ID shared by every
// process that might run MigrateAndSeed concurrently (the api and consumer
// binaries both do, and either may run with more than one replica).
// pg_advisory_xact_lock serializes them so "CREATE TABLE IF NOT EXISTS"
// never races against Postgres's own system catalogs, and it releases
// automatically when the transaction ends - no separate unlock needed.
const migrationLockKey = 7823642091

func MigrateAndSeed(ctx context.Context, pool *pgxpool.Pool) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin migration tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op if already committed

	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock($1)`, int64(migrationLockKey)); err != nil {
		return fmt.Errorf("acquiring migration lock: %w", err)
	}
	if _, err := tx.Exec(ctx, schema); err != nil {
		return fmt.Errorf("applying schema: %w", err)
	}
	if _, err := tx.Exec(ctx, seedData); err != nil {
		return fmt.Errorf("seeding data: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit migration tx: %w", err)
	}
	return nil
}

type Account struct {
	ID           int64     `json:"id"`
	OwnerName    string    `json:"owner_name"`
	BalanceCents int64     `json:"balance_cents"`
	Balance      string    `json:"balance"`
	Currency     string    `json:"currency"`
	CreatedAt    time.Time `json:"created_at"`
}

var ErrAccountNotFound = errors.New("account not found")

func GetAccount(ctx context.Context, pool *pgxpool.Pool, id int64) (*Account, error) {
	row := pool.QueryRow(ctx,
		`SELECT id, owner_name, balance_cents, currency, created_at FROM accounts WHERE id = $1`,
		id,
	)

	var a Account
	if err := row.Scan(&a.ID, &a.OwnerName, &a.BalanceCents, &a.Currency, &a.CreatedAt); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrAccountNotFound
		}
		return nil, fmt.Errorf("querying account %d: %w", id, err)
	}

	a.Balance = fmt.Sprintf("%.2f", float64(a.BalanceCents)/100)
	return &a, nil
}

// RecordAuditIfNew is the idempotent side effect the consumer performs for
// each event. It inserts into processed_events and audit_log inside one
// transaction: if event_id already exists, the INSERT ... ON CONFLICT DO
// NOTHING affects zero rows, so the whole transaction is a no-op and we
// report the event as a duplicate. Otherwise both rows commit together,
// so "processed" and "effect recorded" can never drift apart even if the
// process crashes mid-transaction (Postgres just rolls it back).
func RecordAuditIfNew(ctx context.Context, pool *pgxpool.Pool, eventID string, accountID int64, eventType string, occurredAt time.Time) (inserted bool, err error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return false, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op if already committed

	tag, err := tx.Exec(ctx,
		`INSERT INTO processed_events (event_id) VALUES ($1) ON CONFLICT (event_id) DO NOTHING`,
		eventID,
	)
	if err != nil {
		return false, fmt.Errorf("insert processed_events: %w", err)
	}

	if tag.RowsAffected() == 0 {
		// Already processed by an earlier delivery of the same event; the
		// side effect happened exactly once back then, so there's nothing
		// more to do now.
		return false, nil
	}

	if _, err := tx.Exec(ctx,
		`INSERT INTO audit_log (event_id, account_id, event_type, occurred_at) VALUES ($1, $2, $3, $4)`,
		eventID, accountID, eventType, occurredAt,
	); err != nil {
		return false, fmt.Errorf("insert audit_log: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return false, fmt.Errorf("commit tx: %w", err)
	}

	return true, nil
}
