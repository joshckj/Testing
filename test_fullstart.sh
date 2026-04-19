#!/bin/bash
# =============================================================================
# test_full_start.sh — Test full_start.sh without Docker Hub
# =============================================================================
# Simulates a brand new user by:
#   1. Removing all gas_leak_service containers and volumes
#   2. Removing all gas_leak_service images (forces rebuild from local Dockerfiles)
#   3. Running full_start.sh but skipping the Docker Hub pull step
#
# This verifies everything works from scratch using only local code.
#
# Usage:
#   chmod +x test_full_start.sh
#   ./test_full_start.sh
# =============================================================================

set -e

echo "==============================================================="
echo "  TEST — SIMULATING NEW USER SETUP"
echo "==============================================================="

# ── Step 1: Remove all gas_leak_service containers ─────────────────
echo ""
echo "[Test 1/4] Removing all gas_leak_service containers..."

OUR_CONTAINERS="postgres gasleakagent nginx ingestion retrain"

for c in $OUR_CONTAINERS; do
  if docker ps -a --format '{{.Names}}' | grep -q "^${c}$"; then
    docker stop $c 2>/dev/null
    docker rm $c 2>/dev/null
    echo "  Removed container: $c"
  fi
done

echo "  [OK] Containers removed"

# ── Step 2: Remove all gas_leak_service volumes ────────────────────
echo ""
echo "[Test 2/4] Removing gas_leak_service volumes..."

docker volume rm gas_leak_service_postgres_data 2>/dev/null && echo "  Removed: postgres volume" || true

echo "  [OK] Volumes removed"

# ── Step 3: Remove gas_leak_service images (force full rebuild) ────
echo ""
echo "[Test 3/4] Removing gas_leak_service images..."

# Remove locally built images
docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "gas_leak_service|gasleakagent|ingestion|retrain" | while read img; do
  docker rmi $img 2>/dev/null && echo "  Removed image: $img" || true
done

# Remove pulled images from Docker Hub
docker rmi joshchankj/gasleakagent_base:latest 2>/dev/null && echo "  Removed: joshchankj/gasleakagent_base" || true
docker rmi joshchankj/ingestion_base:latest 2>/dev/null && echo "  Removed: joshchankj/ingestion_base" || true
docker rmi joshchankj/retrain_base:latest 2>/dev/null && echo "  Removed: joshchankj/retrain_base" || true

# Remove model file to simulate fresh start
rm -f build/models/gasleakmodel.cbm && echo "  Removed: gasleakmodel.cbm" || true

echo "  [OK] Images removed — will rebuild from local Dockerfiles"

# ── Step 4: Run full_start.sh ──────────────────────────────────────
echo ""
echo "[Test 4/4] Running full_start.sh..."
echo ""
echo "==============================================================="
echo "  STARTING FULL SETUP — SIMULATED NEW USER"
echo "==============================================================="

# ── Check prerequisites ────────────────────────────────────────────
echo ""
echo "[1/8] Checking prerequisites..."

if [ ! -f ".env" ]; then
  echo "  [ERROR] Root .env missing."
  echo "  Run: cp .env.example .env"
  exit 1
fi

if [ ! -f "data/raw_data/dmis_main_leaks.csv" ]; then
  echo "  [ERROR] data/raw_data/dmis_main_leaks.csv missing."
  exit 1
fi

if [ ! -f "data/raw_data/pipe_data_files.csv" ]; then
  echo "  [ERROR] data/raw_data/pipe_data_files.csv missing."
  exit 1
fi

echo "  [OK] All prerequisites met"

# ── Skip Docker Hub pull — build locally instead ───────────────────
echo ""
echo "[2/8] Skipping Docker Hub pull — building from local Dockerfiles..."
echo "  (In production full_start.sh pulls from joshchankj Docker Hub)"
echo "  [OK] Skipped"

# ── Start PostgreSQL ───────────────────────────────────────────────
echo ""
echo "[3/8] Starting PostgreSQL..."
docker-compose up -d postgres

echo "  Waiting for PostgreSQL to be healthy..."
until docker inspect postgres --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; do
  sleep 2
  echo -n "."
done
echo ""
echo "  [OK] PostgreSQL is healthy"

# ── Run ingestion ──────────────────────────────────────────────────
echo ""
echo "[4/8] Loading CSV data into PostgreSQL..."
docker-compose --profile ingest up --build ingestion

echo "  [OK] Data loaded"

# ── Retrain model ──────────────────────────────────────────────────
echo ""
echo "[5/8] Training CatBoost model..."
echo "  This may take a few minutes..."
docker-compose --profile retrain run --build retrain

if [ ! -f "build/models/gasleakmodel.cbm" ]; then
  echo "  [ERROR] Model file not produced."
  exit 1
fi

echo "  [OK] Model trained"

# ── Start gasleakagent + nginx ─────────────────────────────────────
echo ""
echo "[6/8] Starting gasleakagent and nginx..."
docker-compose up -d --build gasleakagent nginx

echo "  [OK] Services started"

# ── Health check ───────────────────────────────────────────────────
echo ""
echo "[7/8] Running health check..."
sleep 5

HEALTH_OK=false
for i in 1 2 3 4 5; do
  if curl -s http://localhost:8000/api/v1/health | grep -q "ok"; then
    HEALTH_OK=true
    break
  fi
  echo "  Waiting... (attempt $i/5)"
  sleep 3
done

if [ "$HEALTH_OK" = true ]; then
  echo "  [OK] Health check passed"
else
  echo "  [WARN] Health check failed"
  echo "  Check: docker-compose logs gasleakagent"
fi

# ── Summary ────────────────────────────────────────────────────────
echo ""
echo "==============================================================="
echo "  TEST COMPLETE"
echo "==============================================================="
echo ""
echo "  Chat UI         : http://localhost:8000"
echo "  Health check    : http://localhost:8000/api/v1/health"
echo ""
echo "  Running containers:"
docker ps --format "    {{.Names}} — {{.Status}}"
echo ""
echo "  Test result:"

ALL_RUNNING=true
for c in postgres gasleakagent nginx; do
  if docker ps --format '{{.Names}}' | grep -q "^${c}$"; then
    echo "    [OK] $c is running"
  else
    echo "    [FAIL] $c is NOT running"
    ALL_RUNNING=false
  fi
done

if [ "$HEALTH_OK" = true ] && [ "$ALL_RUNNING" = true ]; then
  echo ""
  echo "  ✓ ALL TESTS PASSED — full_start.sh works for new users"
else
  echo ""
  echo "  ✗ SOME TESTS FAILED — check logs above"
fi

echo ""
echo "==============================================================="
