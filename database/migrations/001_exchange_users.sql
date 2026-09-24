-- Reference schema for replacing the demo in-memory user store with PostgreSQL.
CREATE TABLE IF NOT EXISTS exchange_users (
  user_id BIGINT PRIMARY KEY,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
