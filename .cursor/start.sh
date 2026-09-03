#!/usr/bin/env bash
# Cloud Agent per-boot hook: bring PostgreSQL up before the dev servers start.
# Runs on every environment start, so it must tolerate an already-running
# cluster and reach a clear ready/fail state.
set -euo pipefail

# Cursor Cloud secrets may use Stripe_secret_key. Canonical names stay STRIPE_*.
if [ -z "${STRIPE_SECRET_KEY:-}" ] && [ -n "${Stripe_secret_key:-}" ]; then
  export STRIPE_SECRET_KEY="$Stripe_secret_key"
fi
if [ -z "${STRIPE_PUBLISHABLE_KEY:-}" ] && [ -n "${Stripe_publishable_key:-}" ]; then
  export STRIPE_PUBLISHABLE_KEY="$Stripe_publishable_key"
fi
if [ -z "${STRIPE_WEBHOOK_SECRET:-}" ] && [ -n "${Stripe_webhook_secret:-}" ]; then
  export STRIPE_WEBHOOK_SECRET="$Stripe_webhook_secret"
fi

sudo pg_ctlcluster 16 main start 2>/dev/null || true

for _ in $(seq 1 30); do
  if pg_isready -h localhost -U postgres >/dev/null 2>&1; then
    echo "PostgreSQL ready"
    exit 0
  fi
  sleep 1
done

echo "PostgreSQL did not become ready in time" >&2
exit 1
