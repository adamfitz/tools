#!/usr/bin/env bash
set -euo pipefail

echo "==> Updating all Go dependencies..."
go get -u ./...

echo "==> Tidying modules..."
go mod tidy

echo "==> Cleaning module cache..."
go clean -modcache

echo "==> Re-downloading modules..."
go mod download

echo "==> Building project..."
go build ./...

echo "==> Running govulncheck..."
govulncheck ./... || true

echo "==> Running grype..."
grype . -o table

echo "==> Done."
