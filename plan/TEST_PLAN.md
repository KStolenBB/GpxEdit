# GPX Track Editor — TDD Test Plan

This document defines the executable test inventory for first-edition scope.
`plan/PLAN.md` remains the high-level product and architecture contract; this
file is the implementation-focused TDD companion.

- This file tracks the MVP-first test inventory.
- Hardening-track features from `plan/PLAN.md` get dedicated tests only when
  they are pulled into the active delivery scope.

## TDD Workflow

- For each feature/bug: write a failing test first, implement minimal code to
  pass, then refactor with tests green.
- Prefer narrow tests that validate one contract/behavior at a time.
- Add regression tests for every bug fix.

## Backend Test Plan (pytest)

### Unit tests

- Distance calculation (Haversine) matches documented frontend contract.
- Elevation gain uses the configured noise threshold and ignores micro-noise.
- Estimated duration follows speed precedence: route speed -> user default ->
  system default (5 km/h).
- Coordinate normalization rounds to 6 decimal places.
- Validation rejects NaN/Infinity and out-of-range coordinates.

### API contract tests

- Auth: register, login (httpOnly cookie set), logout (cookie cleared), `GET
  /auth/me`, `PUT /auth/me` profile updates.
- Password policy checks: minimum length and email/name-derived rejection.
- Route ownership: cross-user access returns `404`, never `403`.
- Route listing excludes points and is ordered by `updated_at` descending.
- `PUT /routes/{id}` and `PUT /routes/{id}/points` enforce optimistic
  concurrency; stale writes return `409` with `ROUTE_VERSION_CONFLICT` and
  `current_version`.
- Conflict retry contract: retrying after a refetch with the latest `version`
  and `overwrite_intent=true` succeeds; repeating the retry with a stale version
  still returns `409`.
- Error envelope consistency: `error.code`, `error.message`, optional
  `error.details`, `request_id`.

### Route save/import pipeline tests

- `PUT /routes/{id}/points` replaces all points atomically.
- Incoming point elevation is ignored for editor save and stored as null before
  enrichment.
- GPX import preserves embedded `<ele>` values when present.
- Elevation enrichment:
  - full success path;
  - partial failure/timeout still succeeds with partial stats flags;
  - sampling at `ELEVATION_LOOKUP_MAX_POINTS` cap;
  - correct `elevation_is_partial` and `elevation_coverage_ratio`.
- GPX import warnings include skipped invalid points and flattened segments.
- GPX import fails clearly when no valid points remain.

### GPX and limits tests

- Malformed XML import returns clear, structured error.
- Multi-segment GPX input is flattened in-order into one route.
- File size cap (`GPX_MAX_FILE_SIZE_MB`) and point cap (50,000) are enforced.
- `PUT /routes/{id}/points` max body size (`ROUTE_POINTS_MAX_BODY_MB`) is
  enforced.
- Export returns valid GPX generated from stored points and current metadata.

## Frontend Test Plan (Vitest + React Testing Library)

### Store/unit tests

- `editorStore` add/move/delete updates points, dirty state, and derived live
  distance.
- Undo/redo stack behavior for add/move/delete and save checkpoint semantics.
- IndexedDB draft persistence/restore prompt logic keyed by route ID.
- 409 conflict handling flow keeps local edits and presents retry/reload options.
- 401 on save triggers in-place re-auth flow and retries one interrupted save.

### Component/integration tests

- Dashboard route list and create/import flows.
- Editor controls: save, undo/redo, delete selected point.
- Statistics rendering: distance live estimate marker and authoritative value
  after save.
- Elevation profile shows explicit partial/missing-data indication, not silent
  interpolation.
- Tile failure state shows explicit map-unavailable overlay.
- Accessibility baseline: keyboard access for primary actions, focus visibility,
  non-color cues for partial elevation.

## Cross-Stack Contract Tests

- Shared fixture suite verifies frontend/backend parity for:
  - Haversine distance outputs;
  - elevation gain threshold behavior.
- CI gate fails when contract fixtures diverge across stacks.

## Hardening-Track Tests (when scheduled)

- Breached-password rejection and password-reset request/redeem flow.
- Login and route-mutation rate limiting behavior.
- Periodic session-expiry warning banner behavior.
- Optional `Idempotency-Key` support for `POST /routes` and
  `POST /routes/import-gpx`.
- Self-serve account deletion/data-export endpoint coverage.

## Manual Verification Checklist

- Validate Kartverket topo tile loading and attribution display.
- Validate elevation lookup behavior against a known sample route.
- Validate GPX import/export round-trip with real-world files.

## Hardening-Track Manual Verification (when scheduled)

- Validate orthophoto tile loading and layer toggle behavior.
- Validate Stedsnavn search relevance and debounce behavior.

## Execution Order (First Edition)

1. Backend calculation units and API auth/route contracts.
2. Backend save/import pipeline and GPX edge-case tests.
3. Frontend store/unit behavior tests.
4. Frontend component/integration tests.
5. Cross-stack contract fixtures and parity checks.
6. Manual verification before release.
