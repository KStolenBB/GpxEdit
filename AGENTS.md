# AGENTS Guide for GpxEdit

This file is for coding agents working in this repository.
Follow these rules unless the user explicitly asks for something different.

## Repository Snapshot

- Current checked-in files are minimal: `plan/PLAN.md` and `scripts/install-docker-ubuntu.sh`.
- `plan/PLAN.md` defines the intended architecture and conventions.
- Planned stack: React + TypeScript frontend, FastAPI backend, PostgreSQL/PostGIS, Alembic, pytest, Vitest.

## Rule Sources Checked

- Checked `.cursor/rules/`: not present.
- Checked `.cursorrules`: not present.
- Checked `.github/copilot-instructions.md`: not present.
- Therefore, this `AGENTS.md` is the primary in-repo agent guidance.

## Agent Workflow Notes

- Prefer small, focused edits over broad rewrites.
- Preserve existing file patterns and naming.
- Avoid introducing new dependencies without clear need.
- Keep plans and contracts in `plan/PLAN.md` as source of truth.

## Environment and Setup Commands

Use these commands when corresponding folders exist.

### Docker and Postgres

- Install Docker on Ubuntu: `sudo bash scripts/install-docker-ubuntu.sh`
- Start DB container:
  - `docker run --name gpxedit-db -e POSTGRES_PASSWORD=secret -e POSTGRES_DB=gpxedit -p 5432:5432 -d postgres:18.3`

### Backend (FastAPI)

- Create venv: `python -m venv .venv`
- Activate venv: `source .venv/bin/activate`
- Install deps: `pip install -r requirements.txt`
- Start dev server: `uvicorn main:app --reload`

### Frontend (Vite + React)

- Install deps: `npm install`
- Start dev server: `npm run dev`

## Lint / Format / Typecheck Commands

Prefer package scripts first (`npm run <script>`, `make <target>`, or tool wrappers).
If scripts are missing, use these defaults.

### Backend Python defaults

- Lint: `ruff check .`
- Format: `ruff format .`
- Type check: `mypy .`

### Frontend TypeScript defaults

- Lint: `npm run lint` (or `eslint .`)
- Format check: `npm run format:check` (or `prettier --check .`)
- Format write: `npm run format` (or `prettier --write .`)
- Type check: `npm run typecheck` (or `tsc --noEmit`)

## Test Commands

Run tests from the service directory (`backend/` or `frontend/`) when those folders exist.

### Backend tests (pytest)

- All tests: `pytest`
- Single file: `pytest tests/test_routes.py`
- Single test by node id: `pytest tests/test_routes.py::test_replace_points`
- Filter by name: `pytest -k "replace_points and not slow"`

### Frontend tests (Vitest)

- All tests: `npm test` or `npm run test`
- Single file: `npx vitest run src/features/editor/editorStore.test.ts`
- Single test by name: `npx vitest run -t "updates distance on point move"`

## Code Style Guidelines

Apply these conventions unless a stricter local config exists.

### Imports

- Keep imports sorted and grouped: standard library, third-party, local modules.
- Avoid unused imports.
- Prefer explicit imports over wildcard imports.
- In TS, prefer absolute imports only if the project already configures path aliases.

### Formatting

- Let formatter/linter decide final formatting; do not hand-format against tools.
- Keep lines reasonably short (target 100 chars, match project config if present).

### Types and schemas

- Python: use type hints on public functions and complex internal helpers.
- TypeScript: avoid `any`; prefer exact domain types and discriminated unions.
- Validate external input at boundaries (request bodies, query params, file uploads).

### Naming

- Python files/functions/variables: `snake_case`.
- Python classes: `PascalCase`.
- TS variables/functions: `camelCase`.
- TS components/classes/types: `PascalCase`.
- Constants/env keys: `UPPER_SNAKE_CASE`.
- Use domain names from plan (`route`, `route_points`, `estimated_duration_min`, etc.).

### Error handling

- Fail fast on invalid input with clear, structured errors.
- Do not swallow exceptions silently.
- Preserve machine-readable error codes for frontend handling.

### State and side effects

- Keep pure calculations separate from IO and network calls.
- Make backend writes transactional when multiple tables are affected.

## Testing Expectations

- Add or update tests for behavior changes, not only for new files.
- Prefer focused unit tests for calculations and validations.
- Add integration tests for API contracts and persistence flows.
- For bug fixes, include a regression test that fails before and passes after.
- Keep fixtures realistic but minimal.

## Agent Execution Checklist

- Identify affected layer(s): frontend, backend, database, infra.
- Read existing patterns in nearby files before editing.
- Implement minimal change that satisfies request.
- Run relevant lint/typecheck/tests; at least run targeted tests.
- Report what changed, where, and how to verify.

## Safety and Scope

- Never commit secrets or credentials.
- Do not perform destructive database or git operations unless asked.
- Prefer explicit error paths and observable failures over silent fallback.
- Keep changes scoped to requested outcome; defer speculative refactors.

## If Code Is Still Scaffolding-Only

When requested work assumes code that is not yet present:

- Create files in expected service directories (`backend/`, `frontend/`) only when requested.
- Keep initial structure consistent with `plan/PLAN.md`.
- Add scripts in `package.json`/tool config early so single-test commands work.
- Update this `AGENTS.md` when concrete tooling choices differ from defaults.
