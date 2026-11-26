-- Signing in on another device (POST /v1/me/sign-in-code, POST
-- /v1/auth/code): a short code the signed-in device shows, kept hashed like
-- the session tokens, used once and only for a few minutes.
CREATE TABLE sign_in_codes (
  code_hash  bytea PRIMARY KEY,
  account_id bigint NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sign_in_codes_account ON sign_in_codes (account_id);
