# GPX Track Editor - Implementation Plan

This implementation plan is aligned with `plan/PLAN.md` and `AGENTS.md`. It is organized as phased TDD work with explicit acceptance criteria so first-edition scope can be verified, not inferred.

- Phases 1-7 deliver the MVP slice first.
- Phase 8 is the optional hardening track from `plan/PLAN.md`.

## Phase 1: Scaffolding, Configuration, and Test Harness
- Infrastructure: start PostgreSQL + PostGIS Docker container and document local bootstrap commands.
- Backend setup: create `backend/` service skeleton, install runtime + dev dependencies, configure settings loader, and set up `pytest` with DB fixtures.
- Frontend setup: create `frontend/` Vite React + TypeScript app, install test tooling (`vitest`, React Testing Library), and shared app providers for tests.
- Configuration baseline: create backend/frontend `.env.example` files with required keys from plan (`JWT_EXPIRES_MINUTES`, `ELEVATION_THRESHOLD_M`, `VITE_ELEVATION_THRESHOLD_M`, size/point limits).

Acceptance criteria:
- Local `pytest` and `vitest` both run with at least one smoke test each.
- Environment variables required by first-edition scope are documented and load correctly.

## Phase 2: Data Model and Migrations (TDD)
- Tests first: write DB-level tests for schema constraints and invariants (`lower(email)` uniqueness behavior, positive numeric checks, point order uniqueness/checks, version >= 1).
- Implement SQLAlchemy + GeoAlchemy2 models for `users`, `routes`, `route_points`.
- Add Alembic migrations for tables, constraints, and indexes.
- Implement derived geometry maintenance strategy (`route_points.geom` from lat/lon and cached `routes.geom` update path).

Acceptance criteria:
- `alembic upgrade head` builds schema from zero.
- DB tests prove key constraints in `PLAN.md` are enforced.

## Phase 3: Auth, Session, and Security Baseline (TDD)
- Backend tests first for endpoints: `POST /auth/register`, `POST /auth/login`, `POST /auth/logout`, `GET /auth/me`, `PUT /auth/me`.
- Add tests for password policy (minimum length and email/name similarity checks), cookie attributes, and invalid credential handling.
- Implement JWT cookie session with configured algorithm/expiry claims and explicit auth error codes.
- Frontend tests for auth screens and stores, including session presence state and auth error handling.

Acceptance criteria:
- Auth API contract is covered by tests, including user profile update.
- MVP auth/session behavior is covered by targeted tests and ready for editor flows.

## Phase 4: Route API Contracts and Save Pipeline (TDD)
- Backend tests first for route endpoints: list/create/read/update/delete, `PUT /routes/{id}/points`, import/export.
- Add ownership tests that assert `404` for non-owned routes.
- Add optimistic concurrency tests for versioned writes and `409 ROUTE_VERSION_CONFLICT` payload with `current_version`.
- Add conflict retry tests for the explicit `overwrite_intent=true` force-save contract after refetch.
- Add validation tests: coordinate ranges, NaN/Infinity rejection, 6-decimal normalization, file/body size and point-count limits.
- Add save-pipeline tests: replace-all points in one transaction, ignore incoming elevations on editor save, elevation enrichment cap/sampling, and partial metadata (`elevation_is_partial`, coverage ratio).
- Add route stat tests: Haversine distance, thresholded elevation gain, estimated duration speed precedence.

Acceptance criteria:
- All route endpoints conform to documented response/error envelope and conflict behavior.
- Save/import succeeds with partial elevation failures while marking statistics as partial.

## Phase 5: GPX Import/Export and Integration Reliability (TDD)
- Backend tests for GPX edge fixtures: empty, malformed XML, all-invalid points, multi-track/multi-segment flattening, sparse elevations, and limit boundaries.
- Implement GPX import as atomic route + points creation with warnings array for non-fatal issues (e.g., flattened segments, skipped invalid points).
- Implement GPX export from stored route points only (single continuous segment output for first edition).
- Add outbound timeout/retry bounds around elevation provider calls; verify partial-failure behavior.

Acceptance criteria:
- GPX import/export behavior matches first-edition flattening and warning rules.
- Integration tests prove deterministic behavior when elevation service is slow/failing.

## Phase 6: Frontend Editor Core (TDD)
- Frontend tests first for `editorStore`: add/move/delete points, undo/redo semantics, dirty-state tracking, and save-checkpoint behavior.
- Implement map editor page with Kartverket tile layers, point editing interactions, metadata editor, and manual save flow.
- Implement live local distance estimate and estimated duration preview using the same documented Haversine + threshold contract values.
- Ensure large-route handling path exists (separate full-resolution source geometry vs simplified render geometry).

Acceptance criteria:
- Core editor actions are test-covered and responsive for realistic point volumes.
- Manual save is explicit and unsaved state is visible.

## Phase 7: Frontend Recovery, Conflict UX, and Integrations (TDD)
- Tests first for periodic draft persistence (IndexedDB + lightweight recovery marker) keyed by route ID, restore/discard prompt, and clear-on-save behavior.
- Implement 401-on-save in-place re-auth modal that preserves editor state and retries interrupted save exactly once after successful re-auth.
- Implement 409 conflict modal flow (reload latest vs force-save retry-once).
- Implement elevation profile with explicit visual treatment for interpolated/missing spans and non-color cues.
- Implement map tile failure overlay.

Acceptance criteria:
- Session expiry and conflict paths are recoverable without silent data loss.
- Partial elevation data is clearly communicated in UI.

## Phase 8: Hardening Track (Optional Before Broader Rollout)
- Add breached-password rejection hook/provider coverage.
- Implement password reset/account recovery request + redeem flow.
- Add login and route-mutation rate limiting.
- Add periodic session-expiry warning banner.
- Add place-name search, orthophoto toggle, and optional `Idempotency-Key` support.
- Add self-serve account deletion/data-export endpoints and advanced metrics/alerts/runbooks.

Acceptance criteria:
- Any hardening-track feature pulled into scope ships with targeted tests and updated docs.

## Phase 9: Final Validation and CI Readiness
- Run full backend/frontend tests and targeted regression tests for concurrency, import limits, and save recovery flows.
- Run quality gates: `ruff check .`, `ruff format --check .` (or formatter command in use), `mypy .`, frontend lint/typecheck/test scripts.
- Perform manual verification checklist for first-edition critical paths (auth lifecycle, route CRUD, import/edit/save/export).
- Document operational defaults and runbooks (env keys, migration process, secret handling, backup/restore expectations).

Acceptance criteria:
- CI-equivalent checks pass locally.
- First-edition contract in `plan/PLAN.md` is traceable to implemented tests and behaviors.
