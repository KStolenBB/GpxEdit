# GPX Track Editor

A web-based GPX track editor that allows users to create, import, edit, and export GPX routes. Built with React, FastAPI, and PostGIS, featuring integrations with Kartverket for map tiles, elevation data, and place name search.

## Documentation

- [Application Plan](plan/PLAN.md)
- [Implementation Plan](plan/IMPLEMENTATION_PLAN.md)
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

### Database

Start the PostGIS container:

```bash
docker run --name gpxedit-db -e POSTGRES_PASSWORD=secret -e POSTGRES_DB=gpxedit -p 5432:5432 -d postgres:18.3
```

*(Note: Use `scripts/install-docker-ubuntu.sh` if you need to install Docker on Ubuntu).*

### Backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
alembic upgrade head
uvicorn main:app --reload
```

### Frontend

```bash
cd frontend
npm install
npm run dev
```
