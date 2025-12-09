#!/bin/sh

set -e

echo "Running DB migrations..."

migrate \
  -path=/migrations \
  -database="$DATABASE_URL" \
  $@

echo "Migration completed successfully."
