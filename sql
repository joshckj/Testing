#!/bin/bash
# =============================================================================
# full_start.sh — Complete setup for new colleagues
# =============================================================================
# One script to set up everything from scratch.
# Pulls Docker images, starts PostgreSQL, loads data, starts services.
#
# Prerequisites
# -------------
# 1. Docker Desktop installed and running
# 2. gasleakagent/.env, retrain/.env, ingestion/.env, and root .env filled in
# 3. CSV files in data/raw_data/
#    - dmis_main_leaks.csv
#    - pipe_data_files.csv
# 4. Model in build/models/gasleakmodel.cbm
#
# Usage
# -----
#   chmod +x full_start.sh
#   ./full_start.sh
# =============================================================================

set -e   # exit on any error

echo "==============================================================="
echo "  GAS LEAK SERVICE — FULL SETUP"
echo "==============================================================="

# ── Check prerequisites ─────────────────────────────────────────────
echo ""
echo "[1/6] Checking prerequisites..."

if ! command -v docker &> /dev/null; then
  echo "  [ERROR] Docker not installed. Install Docker Desktop first."
  exit 1
fi

if ! docker info &> /dev/null; then
  echo "  [ERROR] Docker is not running. Start Docker Desktop."
  exit 1
fi

if [ ! -f ".env" ]; then
  echo "  [ERROR] Root .env missing. Copy .env.example to .env and fill in POSTGRES_* vars."
  exit 1
fi

if [ ! -f "gasleakagent/.env" ]; then
  echo "  [ERROR] gasleakagent/.env missing. Copy from .env.example and fill in values."
  exit 1
fi

if [ ! -f "ingestion/.env" ]; then
  echo "  [ERROR] ingestion/.env missing. Copy from .env.example and fill in values."
  exit 1
fi

if [ ! -f "retrain/.env" ]; then
  echo "  [ERROR] retrain/.env missing. Copy from .env.example and fill in values."
  exit 1
fi

if [ ! -f "data/raw_data/dmis_main_leaks.csv" ]; then
  echo "  [ERROR] data/raw_data/dmis_main_leaks.csv missing. Place your DMIS CSV here."
  exit 1
fi

if [ ! -f "data/raw_data/pipe_data_files.csv" ]; then
  echo "  [ERROR] data/raw_data/pipe_data_files.csv missing. Place your pipe CSV here."
  exit 1
fi

if [ ! -f "build/models/gasleakmodel.cbm" ]; then
  echo "  [ERROR] build/models/gasleakmodel.cbm missing. Place your chosen model here."
  exit 1
fi

echo "  [OK] All prerequisites met"

# ── Pull Docker images ──────────────────────────────────────────────
echo ""
echo "[2/6] Pulling Docker images from Docker Hub..."
docker pull joshchankj/gasleakagent_base:latest
docker pull joshchankj/ingestion_base:latest
docker pull joshchankj/retrain_base:latest
echo "  [OK] Images pulled"

# ── Start PostgreSQL ────────────────────────────────────────────────
echo ""
echo "[3/6] Starting PostgreSQL..."
docker-compose up -d postgres

echo "  Waiting for PostgreSQL to be healthy..."
until docker inspect postgres --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; do
  sleep 2
  echo -n "."
done
echo ""
echo "  [OK] PostgreSQL is healthy"

# ── Run ingestion to load CSVs into PostgreSQL ──────────────────────
echo ""
echo "[4/6] Running ingestion to load CSVs into PostgreSQL..."
docker-compose --profile ingest up --build ingestion
echo "  [OK] Data loaded into PostgreSQL"

# ── Build and start gasleakagent + nginx ────────────────────────────
echo ""
echo "[5/6] Building and starting gasleakagent + nginx..."
docker-compose up -d --build gasleakagent nginx
echo "  [OK] Services started"

# ── Health check ─────────────────────────────────────────────────────
echo ""
echo "[6/6] Running health check..."
sleep 5

if curl -s http://localhost:8000/api/v1/health | grep -q "ok"; then
  echo "  [OK] Health check passed"
else
  echo "  [WARN] Health check failed — check logs with: docker-compose logs gasleakagent"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "==============================================================="
echo "  SETUP COMPLETE"
echo "==============================================================="
echo ""
echo "  Chat UI         : http://localhost:8000"
echo "  Health check    : http://localhost:8000/api/v1/health"
echo ""
echo "  Running containers:"
docker ps --format "  {{.Names}} — {{.Status}}"
echo ""
echo "  Useful commands:"
echo "    docker-compose logs -f gasleakagent   # view logs"
echo "    docker-compose restart gasleakagent   # restart service"
echo "    docker-compose down                    # stop everything"
echo ""
echo "==============================================================="
