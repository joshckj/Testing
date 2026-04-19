#!/bin/bash
# =============================================================================
# full_start.sh — Gas Leak Service Full Setup
# =============================================================================
# Sets up everything from scratch in one command.
# Pulls images, wipes previous containers, loads data, retrains model,
# starts services.
#
# Prerequisites:
#   1. Docker Desktop installed and running
#   2. Root .env file filled in (cp .env.example .env)
#   3. CSV files in data/raw_data/
#      - dmis_main_leaks.csv
#      - pipe_data_files.csv
#
# Usage:
#   chmod +x full_start.sh
#   ./full_start.sh
# =============================================================================

set -e

echo "==============================================================="
echo "  GAS LEAK SERVICE — FULL SETUP"
echo "==============================================================="

# ── [1/9] Check prerequisites ──────────────────────────────────────
echo ""
echo "[1/9] Checking prerequisites..."

if ! command -v docker &> /dev/null; then
  echo "  [ERROR] Docker not installed. Install Docker Desktop first."
  exit 1
fi

if ! docker info &> /dev/null; then
  echo "  [ERROR] Docker is not running. Start Docker Desktop."
  exit 1
fi

if [ ! -f ".env" ]; then
  echo "  [ERROR] Root .env missing."
  echo "  Run: cp .env.example .env"
  echo "  Then fill in your credentials."
  exit 1
fi

if [ ! -f "data/raw_data/dmis_main_leaks.csv" ]; then
  echo "  [ERROR] data/raw_data/dmis_main_leaks.csv missing."
  echo "  Place your DMIS CSV here before running."
  exit 1
fi

if [ ! -f "data/raw_data/pipe_data_files.csv" ]; then
  echo "  [ERROR] data/raw_data/pipe_data_files.csv missing."
  echo "  Place your pipe data CSV here before running."
  exit 1
fi

echo "  [OK] All prerequisites met"

# ── [2/9] Pull Docker images from Docker Hub ───────────────────────
echo ""
echo "[2/9] Pulling Docker images from Docker Hub..."
docker pull joshchankj/gasleakagent_base:latest
docker pull joshchankj/ingestion_base:latest
docker pull joshchankj/retrain_base:latest
echo "  [OK] Images pulled"

# ── [3/9] Clean up previous gas_leak_service containers ────────────
echo ""
echo "[3/9] Cleaning up previous gas_leak_service containers..."

OUR_CONTAINERS="postgres gasleakagent nginx ingestion retrain"

for c in $OUR_CONTAINERS; do
  if docker ps -a --format '{{.Names}}' | grep -q "^${c}$"; then
    docker stop $c 2>/dev/null
    docker rm $c 2>/dev/null
    echo "  Removed: $c"
  fi
done

# Remove our postgres volume only — not other projects
docker volume rm gas_leak_service_postgres_data 2>/dev/null && echo "  Removed: postgres volume" || true

echo "  [OK] Clean slate"

# ── [4/9] Start PostgreSQL ─────────────────────────────────────────
echo ""
echo "[4/9] Starting PostgreSQL..."
docker-compose up -d postgres

echo "  Waiting for PostgreSQL to be healthy..."
until docker inspect postgres --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; do
  sleep 2
  echo -n "."
done
echo ""
echo "  [OK] PostgreSQL is healthy"

# ── [5/9] Run ingestion to load CSVs into PostgreSQL ───────────────
echo ""
echo "[5/9] Loading CSV data into PostgreSQL..."
docker-compose --profile ingest up --build ingestion

echo "  [OK] Data loaded into PostgreSQL"

# ── [6/9] Retrain model ───────────────────────────────────────────
echo ""
echo "[6/9] Training CatBoost model..."
echo "  This may take a few minutes..."
docker-compose --profile retrain run --build retrain

# Verify model was produced
if [ ! -f "build/models/gasleakmodel.cbm" ]; then
  echo "  [ERROR] Model file not produced."
  echo "  Check retrain logs: docker-compose logs retrain"
  exit 1
fi

echo "  [OK] Model trained and saved to build/models/gasleakmodel.cbm"

# ── [7/9] Build and start gasleakagent + nginx ─────────────────────
echo ""
echo "[7/9] Starting gasleakagent and nginx..."
docker-compose up -d --build gasleakagent nginx

echo "  [OK] Services started"

# ── [8/9] Health check ─────────────────────────────────────────────
echo ""
echo "[8/9] Running health check..."
sleep 5

HEALTH_OK=false
for i in 1 2 3 4 5; do
  if curl -s http://localhost:8000/api/v1/health | grep -q "ok"; then
    HEALTH_OK=true
    break
  fi
  echo "  Waiting for gasleakagent to be ready... (attempt $i/5)"
  sleep 3
done

if [ "$HEALTH_OK" = true ]; then
  echo "  [OK] Health check passed"
else
  echo "  [WARN] Health check failed — check logs:"
  echo "  docker-compose logs gasleakagent"
fi

# ── [9/9] Summary ─────────────────────────────────────────────────
echo ""
echo "==============================================================="
echo "  SETUP COMPLETE"
echo "==============================================================="
echo ""
echo "  Chat UI         : http://localhost:8000"
echo "  Health check    : http://localhost:8000/api/v1/health"
echo "  PostgreSQL      : localhost:5432"
echo ""
echo "  Running containers:"
docker ps --format "    {{.Names}} — {{.Status}}"
echo ""
echo "  Useful commands:"
echo "    docker-compose logs -f gasleakagent    # view logs"
echo "    docker-compose restart gasleakagent    # restart agent"
echo "    docker-compose down                    # stop everything"
echo "    docker-compose down -v                 # stop + wipe data"
echo ""
echo "==============================================================="
