#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-gpxedit-db}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-secret}"
POSTGRES_DB="${POSTGRES_DB:-gpxedit}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgis/postgis:18-3.5}"
POSTGRES_VOLUME="${POSTGRES_VOLUME:-gpxedit-db-data}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required but was not found on PATH."
  echo "Install it with: sudo bash scripts/install-docker-ubuntu.sh"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not running or not accessible."
  echo "Start Docker and try again."
  exit 1
fi

if docker ps --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then
  echo "Postgres container '${CONTAINER_NAME}' is already running."
  exit 0
fi

if docker ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then
  echo "Starting existing Postgres container '${CONTAINER_NAME}'..."
  docker start "${CONTAINER_NAME}"
  echo "Postgres is available on localhost:${POSTGRES_PORT}."
  exit 0
fi

echo "Creating and starting Postgres container '${CONTAINER_NAME}'..."
docker run \
  --name "${CONTAINER_NAME}" \
  --volume "${POSTGRES_VOLUME}:/var/lib/postgresql/data" \
  -e "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" \
  -e "POSTGRES_DB=${POSTGRES_DB}" \
  -p "${POSTGRES_PORT}:5432" \
  -d "${POSTGRES_IMAGE}"

echo "Postgres container started."
echo "Data volume: ${POSTGRES_VOLUME}"
echo "Connection: postgresql://postgres:${POSTGRES_PASSWORD}@localhost:${POSTGRES_PORT}/${POSTGRES_DB}"
