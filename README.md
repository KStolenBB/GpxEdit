# GPX Track Editor

A web-based GPX track editor that allows users to create, import, edit, and export GPX routes. Built with React, FastAPI, and PostGIS, featuring integrations with Kartverket for map tiles, elevation data, and place name search.

## Current Status

The repository is currently in planning-first mode. Core architecture, implementation phases, and test strategy are documented, while backend/frontend application code is still to be scaffolded.

## Documentation

- [Application Plan](plan/PLAN.md)
- [Implementation Plan](plan/IMPLEMENTATION_PLAN.md)
- [Test Plan](plan/TEST_PLAN.md)
- [Agent Guidelines](AGENTS.md)

## Tech Stack

- **Frontend**: React, TypeScript, Vite, react-leaflet, Zustand, React Query
- **Backend**: FastAPI, Python, SQLAlchemy, GeoAlchemy2, Alembic
- **Database**: PostgreSQL with PostGIS

## Quick Start (Local Development)

### Prerequisites
- Docker
- Python 3.10+
- Node.js 18+

### 1) Start Local Database (optional for planning)

Start the PostGIS container:

```bash
docker run --name gpxedit-db -e POSTGRES_PASSWORD=secret -e POSTGRES_DB=gpxedit -p 5432:5432 -d postgis/postgis:18-3.5
```

Or use the helper script:

```bash
bash scripts/start-postgres-docker.sh
```

*(Note: Use `scripts/install-docker-ubuntu.sh` if you need to install Docker on Ubuntu).*

### 2) Prepare Python Dependencies

Install Python dependencies from the repository root:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 3) Next Development Step

Use `plan/IMPLEMENTATION_PLAN.md` as the source of truth for scaffold and feature build-out order (backend, frontend, migrations, and test harness).

## Planned Runtime Commands

After `backend/` and `frontend/` are scaffolded:

```bash
cd frontend
npm install
npm run dev
```

```bash
cd backend
alembic upgrade head
uvicorn main:app --reload
```
