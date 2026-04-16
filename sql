#!/bin/bash
# =============================================================================
# setup_postgres.sh — Creates a simple PostgreSQL container
# =============================================================================
# Usage:
#   ./setup_postgres.sh
# =============================================================================

# Config
CONTAINER_NAME="mypostgres"
USER="gasleakuser"
PASSWORD="password123"
DB="gasleakdb"
PORT="5432"

echo "Starting PostgreSQL container..."

docker run -d \
  --name $CONTAINER_NAME \
  -e POSTGRES_USER=$USER \
  -e POSTGRES_PASSWORD=$PASSWORD \
  -e POSTGRES_DB=$DB \
  -p $PORT:5432 \
  -v postgres_data:/var/lib/postgresql/data \
  postgres:15

echo ""
echo "Waiting for PostgreSQL to be ready..."
sleep 5

echo ""
echo "PostgreSQL is ready!"
echo ""
echo "Connection details:"
echo "  Host     : localhost"
echo "  Port     : $PORT"
echo "  Database : $DB"
echo "  User     : $USER"
echo "  Password : $PASSWORD"
echo ""
echo "To connect:"
echo "  docker exec -it $CONTAINER_NAME psql -U $USER -d $DB"
echo ""
echo "To stop:"
echo "  docker stop $CONTAINER_NAME"
echo ""
echo "To remove:"
echo "  docker rm -f $CONTAINER_NAME"
