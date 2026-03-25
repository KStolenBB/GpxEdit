# GPX Track Editor — Application Plan

## Stack Summary

| Layer       | Technology                              |
|-------------|-----------------------------------------|
| Frontend    | React + TypeScript                      |
| Mapping     | Leaflet + react-leaflet                 |
| Backend     | FastAPI (Python)                        |
| Database    | PostgreSQL + PostGIS (Docker)           |
| ORM         | SQLAlchemy + GeoAlchemy2 + Alembic      |
| Auth        | Email/password, JWT (httpOnly cookie)   |
| Frontend state | Zustand (client) + React Query (server) |
| GPX parsing | `gpxpy`                                 |
| Elevation   | Kartverket Høydedata API                |

---

## Development approach

- The project follows a Test-Driven Development (TDD) workflow by default.
- For each feature or bug fix, write or update failing tests first, implement the minimal code to pass, then refactor while keeping tests green.
- Changes are not considered complete until relevant automated tests (unit/integration/frontend) pass.
- Detailed test inventory and execution order are maintained in `plan/TEST_PLAN.md`.

---

## Data Model

### `users`
```
id            UUID, primary key
email         not null, case-insensitive (enforced by DB; stored lowercase)
password_hash not null
name          nullable
default_speed_kmh float, nullable
created_at    timestamptz

UNIQUE on lower(email)  -- or PostgreSQL CITEXT-based unique constraint
CHECK(default_speed_kmh IS NULL OR default_speed_kmh > 0)
```

### `routes`
```
id            UUID, primary key
user_id       foreign key → users (ON DELETE CASCADE)
name          not null
geom          geometry(LineString, 4326), nullable  -- Cached/generated for whole route
description   nullable
estimated_speed_kmh  float, nullable
distance_m    float, nullable
elevation_gain_m     float, nullable
estimated_duration_min float, nullable
elevation_is_partial boolean, not null default false
elevation_coverage_ratio float, nullable  -- 0.0 to 1.0
version       integer, not null default 1
created_at    timestamptz
updated_at    timestamptz

INDEX on user_id
INDEX on (user_id, updated_at DESC)
CHECK(estimated_speed_kmh IS NULL OR estimated_speed_kmh > 0)
CHECK(distance_m IS NULL OR distance_m >= 0)
CHECK(elevation_gain_m IS NULL OR elevation_gain_m >= 0)
CHECK(estimated_duration_min IS NULL OR estimated_duration_min >= 0)
CHECK(elevation_coverage_ratio IS NULL OR (elevation_coverage_ratio >= 0 AND elevation_coverage_ratio <= 1))
CHECK(version >= 1)
```

### `route_points`
```
id            UUID, primary key
route_id      foreign key → routes (ON DELETE CASCADE)
lat           float  -- WGS84 decimal degrees
lon           float  -- WGS84 decimal degrees
geom          geometry(Point, 4326)  -- PostGIS geometry type
elevation     float, nullable  -- metres above sea level
point_order   integer

UNIQUE(route_id, point_order)
CHECK(point_order >= 0)
```

Notes on `point_order`:
- Integer ordering works correctly with the first-edition "replace all points"
  strategy,
  since the entire sequence is rewritten on every save.
- Inserting a single point in the middle of a large track using integer order
  would require renumbering all subsequent rows — this is acceptable only
  because the first edition always replaces the full set. If a future edition
  introduces incremental
  point-edit APIs, `point_order` should be migrated to floating-point or
  fractional indexing (e.g. LexoRank) to allow O(1) inserts without
  renumbering. This migration path must be considered when designing future
  editions.

Notes:
- Timestamps per point are intentionally omitted. Since this is an editor, tracks
  will frequently be modified, making any recorded timestamps unreliable.
- The schema intentionally keeps both `lat`/`lon` and `geom` on `route_points`.
  `lat`/`lon` keeps API serialization and validation simple, while `geom` enables
  PostGIS-native operations and spatial indexing/extensions later without having
  to derive point geometry repeatedly.
- `lat`/`lon` is the canonical source for API writes. `geom` is derived from
  those values in the same transaction (application layer or DB trigger), so the
  two representations cannot drift.
- The cached `routes.geom` LineString is retained as a backend-maintained derived
  column so route-level spatial operations, export helpers, and future map/list
  queries can work from a single geometry value instead of rebuilding it from
  all `route_points` rows on demand.
- `routes.updated_at` is backend-managed on every metadata or point mutation and
  should not be accepted from clients.
- GPX files uploaded by the user are parsed server-side, points are stored, and
  the original file is discarded. GPX export generates the file on the fly.
- Imported GPX metadata is preserved only where it maps cleanly to the internal
  route model (for example name, description, and point elevations when present).
- The app uses the term `route points` or `track points` for the editable line on
  the map. GPX waypoint objects are out of scope for the first edition to avoid
  mixing two different concepts.

### Derived route statistics
- `distance_m`, `elevation_gain_m`, and `estimated_duration_min` are route-level
  values maintained by the backend whenever a route is imported or its points are
  replaced.
- `elevation_is_partial` and `elevation_coverage_ratio` are persisted route-level
  metadata so the frontend does not have to infer data completeness.
- `estimated_duration_min` is derived from total route distance and the selected
  `estimated_speed_kmh` value.
- Precedence rule for estimated speed: route-level `estimated_speed_kmh` → user-level
  `default_speed_kmh` → system default (5 km/h).
- Changing `estimated_speed_kmh` on a route (via `PUT /routes/{id}`) immediately
  recomputes and persists `estimated_duration_min` in the same request.
- If elevation data is incomplete (some points have null elevation), `elevation_gain_m`
  is marked as partial and the UI must indicate it is not a complete figure.

### Statistics consistency between frontend and backend
- The frontend computes distance live as the user draws. The backend recomputes
  distance on every save. Both must use the **same algorithm** (Haversine) to
  avoid a visible "jump" in the displayed total after a save.
- Elevation gain calculation must apply a **noise threshold** (e.g. ignore
  cumulative rises below 2 m) on both frontend and backend to avoid inflating
  figures from GPS micro-noise. The threshold value is defined as a documented
  cross-stack contract (not a shared runtime constant), configured explicitly in
  both apps, and verified with shared fixtures/tests. It is documented in
  `.env.example`.
- The elevation noise threshold is configured as `VITE_ELEVATION_THRESHOLD_M` in
  the frontend `.env` and `ELEVATION_THRESHOLD_M` in the backend `.env`. Both
  must match. The canonical value is documented in `.env.example` for both
  projects.
- The frontend live-distance figure is explicitly labelled as an estimate in the
  UI (e.g. "~12.4 km"). The backend-computed value shown after save is the
  authoritative figure and displayed without qualification.

### Editing model
- The first edition treats each saved route as a single ordered polyline made of
  route points.
- Import supports GPX tracks and normalizes them into the internal ordered-point
  model.
- Multiple independent GPX track segments are flattened by concatenating segments
  in order during import. The user is warned when this happens.
- Flattening multi-segment GPX input into a single route is a deliberate
  first-edition product rule, not just an implementation shortcut. Original
  segment boundaries are not stored, and GPX export always writes a single
  continuous track/segment.

---

## Backend — FastAPI

### Auth endpoints
- `POST /auth/register` — create account
- `POST /auth/login`    — return JWT (httpOnly cookie)
- `POST /auth/logout`   — clear cookie
- `GET /auth/me`         — return current authenticated user profile
- `PUT /auth/me`         — update user profile/settings (name, default speed)

### Auth and security notes
- Passwords are hashed with Argon2 or bcrypt, never stored in plain text.
- Password policy is enforced server-side: minimum length 12, reject known weak/
  breached passwords, and reject passwords that trivially contain the user's
  email/name.
- Auth cookies should use `HttpOnly`, `Secure` in production, and `SameSite=Lax`
  by default.
- State-changing requests are protected against CSRF by `SameSite=Lax` cookies
  and strict CORS origin checks. A dedicated CSRF token mechanism (e.g.
  double-submit cookie) is deferred to a future edition — the current
  protections are sufficient for a same-origin SPA where CORS is locked to the
  frontend origin.
- If deployment changes to cross-origin or cross-site auth flows, a dedicated
  CSRF token mechanism becomes mandatory before release.
- Login endpoints should have basic rate limiting to reduce brute-force risk.
- Account recovery is part of the first-edition security baseline: password reset
  uses
  single-use, short-TTL tokens with one-time redemption and rate-limited request
  endpoints. Reset tokens are stored hashed at rest, compared in constant time,
  and invalidated immediately after successful use. Whether email verification is
  required before first login is a deploy-time policy toggle that must be
  explicit in environment config.
- CORS should allow only the local React dev origin in development and the
  deployed frontend origin in production.

### Session strategy
- JWT access token is issued on login and stored as an httpOnly cookie.
- JWT algorithm is explicitly configured (`JWT_ALGORITHM`, default `HS256`) and
  token claims include at least `sub`, `iat`, and `exp`.
- Access token expiry is configurable via `JWT_EXPIRES_MINUTES` (default: 480
  minutes / 8 hours). A longer default reduces the chance of mid-edit session
  interruptions while the re-auth modal still protects against data loss if the
  token does expire.
- No refresh token in the first edition. When the access token expires, the user
  is redirected to log in again.
- `POST /auth/logout` clears the cookie on the client. No server-side token
  blocklist in the first edition.
- JWT signing keys/secrets follow a rotation policy (documented runbook,
  environment-based secret source, staged rollover without downtime).

### Production security baseline
- Cookie attribute policy is explicit per environment (`Secure`, `SameSite`,
  `Domain`, `Path`, `Max-Age`) and documented in backend `.env.example`.
- If TLS is terminated at a reverse proxy/load balancer, backend trusted-proxy
  settings and forwarded-header handling are configured so secure-cookie and
  scheme-sensitive checks remain correct.
- Security headers are enabled in production with explicit defaults:
  `Strict-Transport-Security` (HSTS), `Content-Security-Policy`,
  `X-Content-Type-Options: nosniff`, `Referrer-Policy`, and frame-embedding
  restriction (`X-Frame-Options` or CSP `frame-ancestors`).
- Sensitive account actions (password/email change, account deletion) should
  require recent re-authentication, and MFA can be added as a staged hardening
  step when operating context requires it.
- Session invalidation for compromised accounts is supported operationally: if
  immediate revocation is required, rotate JWT signing secrets/keys and force
  re-login for active sessions.

### Session expiry and data loss prevention
- The "short-lived token + manual save" combination creates a data loss risk: a
  user who draws for longer than the token lifetime will get a 401 on save and
  lose all unsaved work if the frontend simply redirects to login.
- The frontend must handle 401 responses during a save attempt by showing an
  in-place "Session expired — please re-enter your password" modal, keeping all
  editor state intact while the user re-authenticates.
- After successful re-authentication, the frontend automatically retries the
  interrupted save request once so the user does not have to repeat the action.
- Additionally, the frontend should periodically check session validity (e.g.
  every 10 minutes via `GET /auth/me`) and warn the user with a banner if their
  session is about to expire, prompting them to save before it does.

### API abuse protection and limits
- Login endpoint is rate limited per IP and per account identifier (email) with
  temporary lockout/backoff after repeated failures.
- Route mutation endpoints (`POST/PUT/DELETE`) are rate limited per user to
  prevent accidental save storms and abusive traffic.
- GPX import is rate limited per user and constrained by existing size/point
  caps; repeated oversized uploads should be throttled.
- Place-name search requests from the frontend are debounced and additionally
  proxied/rate-limited server-side in production if abuse appears.
- Configurable limits are documented in backend `.env.example` and surfaced with
  safe default values.

### Route endpoints
- `GET    /routes`              — list all routes for logged-in user (returns metadata only, NO points; sorted by `updated_at` descending)
- `POST   /routes`              — create new empty route
- `GET    /routes/{id}`         — get route + all points
- `PUT    /routes/{id}`         — update route metadata (name, description, estimated_speed_kmh); recomputes estimated_duration_min immediately
- `DELETE /routes/{id}`         — delete route and its points
- `PUT    /routes/{id}/points`  — replace all points (MVP approach after any edit)
- `POST   /routes/import-gpx`   — parse uploaded GPX, create new route + points in one atomic operation
- `GET    /routes/{id}/export`  — generate and return a .gpx file on the fly

Notes:
- Replacing all points after each edit keeps the initial editor/backend contract
  simple and easy to reason about.
- Every route endpoint must enforce ownership (`route.user_id == current_user.id`).
- Ownership/authorization response rule for the first edition: if the route
  exists but belongs to
  another user, return `404 Not Found` (never `403`) to avoid resource
  enumeration. `403` is reserved for authenticated users lacking a broader role/
  permission in future role-based features.
- Route mutation endpoints use optimistic concurrency. The client sends the
  current route `version` with `PUT /routes/{id}` and `PUT /routes/{id}/points`;
  the backend rejects stale writes with `409 Conflict`, and any successful
  mutation increments `version`.
- Idempotency policy:
  - `PUT` route metadata and points are idempotent for the same `(route_id,
    version, payload)` tuple.
  - `POST /routes` and `POST /routes/import-gpx` accept an optional
    `Idempotency-Key` header to deduplicate client retries.
- When the frontend receives a `409 Conflict`, it should show a modal informing
  the user that the route was modified elsewhere, offering two options: "Reload
  latest" (discards local changes and fetches the current version) or "Force
  save" (re-fetch latest version, then retry once with overwrite intent using
  the user's current local payload). If another conflict occurs, keep local
  edits and ask the user to reload or retry; do not loop automatically. No
  diff/merge UI in the first edition.
- If route length or edit volume later becomes a performance problem, this can be
  evolved into incremental point operations in a future edition without changing
  the core data model.
- The "replace all" operation must use Postgres bulk inserts (e.g. SQLAlchemy
  `insert().values()` bulk execution) rather than ORM-level `add_all()` to avoid
  slow row-by-row inserts at large point counts (up to 50,000 rows). The old
  points are deleted first in a single `DELETE WHERE route_id = ?` statement,
  followed immediately by the bulk insert, all within a single transaction.
  *(Note: Replacing tens of thousands of rows on every manual save causes heavy
   transaction log churn in PostgreSQL. Monitor DB bloat and track if frequent saves
   demand a switch to incremental updates in a future edition.)*

### Backend integration services
- Elevation lookup is implemented as an internal backend service/module that calls
  Kartverket Høydedata directly during save/import. It is not exposed as a public
  HTTP endpoint in the first edition.

### Input validation
- Latitude must be in range `[-90, 90]`, longitude in `[-180, 180]`. Points
  outside these ranges are rejected with a `422` response.
- NaN, Infinity, and non-numeric coordinate values are rejected.
- Coordinate precision is normalized to 6 decimal places (WGS84) at API
  boundaries to keep payloads stable and avoid noisy diffs.
- Imported GPX files are validated similarly: malformed coordinates cause the
  affected points to be skipped with a warning (not a full import failure),
  unless all points are invalid, in which case the import fails with a clear
  error.
- Uploaded file size is validated before parsing (max 10 MB, configurable via
  `GPX_MAX_FILE_SIZE_MB`). Point count is validated after parsing (max 50,000).
- `PUT /routes/{id}/points` enforces a max request body size (configurable via
  `ROUTE_POINTS_MAX_BODY_MB`) and supports gzip-compressed request bodies in
  production deployments.

### API response contract
- Backend APIs return a consistent JSON envelope for errors:
  - `error.code` (stable machine-readable identifier)
  - `error.message` (user-safe summary)
  - `error.details` (optional field-level/context payload)
  - `request_id` (for log correlation)
- Validation failures return `422` with field-level details in
  `error.details.fields[]` so frontend forms can map errors directly.
- Stale optimistic-concurrency writes return `409 Conflict` with
  `error.code="ROUTE_VERSION_CONFLICT"` and include `current_version`.
- GPX import warnings (e.g. skipped invalid points, flattened segments) are
  returned in a non-fatal `warnings[]` array in the success response.
- Session/auth failures return explicit auth codes (`AUTH_REQUIRED`,
  `SESSION_EXPIRED`) so the frontend can trigger the in-place re-auth flow
  deterministically.

### Save behavior
- The editor uses **manual save** — the user explicitly triggers a save action.
- On save, the backend replaces all route points, then fetches elevation in bulk
  for any points that have null elevation, then recomputes route statistics.
- For editor saves, the backend is authoritative for elevation data: incoming
  point elevations from `PUT /routes/{id}/points` are ignored and stored as null
  before enrichment so moved points can never retain stale elevation values.
  (GPX import is different: embedded `<ele>` values from the uploaded file are
  preserved when present.)
- The frontend should clearly indicate unsaved changes (e.g. a dirty state flag
  in `editorStore`) and warn the user before navigating away with unsaved edits.
- The frontend shows explicit save progress states (e.g. "Saving route...",
  "Finalizing elevation...") because enrichment may add noticeable latency.

### Unsaved state recovery
- The frontend periodically persists the current editor state (points, metadata,
  dirty flag) to `localStorage` keyed by route ID.
- On loading a route in the editor, if a newer local draft exists than the
  server version, the user is prompted: "You have unsaved changes from a previous
  session. Restore or discard?"
- The local draft is cleared on successful save or explicit discard.

### Elevation enrichment limits
- Fetching elevation for every point in bulk during save is not safe at large
  point counts. The following rules apply to protect against rate-limiting and
  request timeouts:
  - Elevation is fetched for a maximum of 1,000 points per save or import.
  - If a route has more than 1,000 points without elevation, the backend samples
    evenly across the full set (e.g. every Nth point) up to the 1,000 point cap,
    and the remaining points are left with null elevation.
  - Route statistics are marked partial when the elevation coverage is incomplete.
  - This limit is configurable via `ELEVATION_LOOKUP_MAX_POINTS` in the backend
    `.env` file.
- When some points have null elevation after sampling, the exported GPX file will
  contain sparse `<ele>` tags. The elevation profile chart in the UI must
  **interpolate** the missing values only for visual continuity (drawing a
  straight line segment between adjacent known elevations) and visually
  distinguish interpolated spans with a dashed line style and legend/label so the
  interpolation is never silent.
- If an uploaded GPX file contains multiple tracks or multiple segments, they are
  flattened into a single ordered polyline by concatenating segments in order. The
  user should be warned in the UI that multi-segment structure was merged.
- If the file contains no valid track points, the import should fail with a clear
  error message.
- Elevation lookup requests use explicit outbound timeouts and bounded retry
  behavior. If enrichment partially fails or times out, the route save/import
  still succeeds, affected points remain null, and route statistics are marked
  partial.

### GPX export behavior
- Export always generates the GPX file from the current edited route points stored
  in the database. There is no concept of "original file" after import.
- Simplification is only applied for frontend rendering. The stored (and exported)
  geometry is always the full-resolution point set.
- Because the first edition flattens imported multi-segment GPX data into one
  ordered polyline, export also emits a single continuous track/segment rather
  than reconstructing original segment boundaries.

### Elevation profile UI
- When some points have null elevation (e.g. due to failed lookups), the elevation
  profile chart should not interpolate silently. It may render dashed
  interpolated spans for continuity, but the missing-data portions must be clearly
  marked in the legend/visual treatment.
- Elevation is fetched in bulk when a route is saved or imported, not live while
  drawing.
- If Kartverket elevation lookup fails for some points, those points remain with
  nullable elevation values and the save still succeeds.
- Users can continue editing even when elevation data is temporarily unavailable.

---

## Frontend — React

### Pages
- `/`                — landing page, login/register or redirect to dashboard
- `/dashboard`       — list of user's routes, create new or upload GPX
- `/editor/:routeId` — the main map editor
- `/settings`        — user profile and default speed settings

### Editor features (first edition)
- Kartverket WMTS topo map as base layer (+ orthophoto toggle)
- Add / move / delete route points on the map
- Draw new track segments click-by-click (manual placement only; no path snapping
  in the first edition — the UI should make freeform drawing obvious to avoid user confusion)
- Undo / redo for point add / move / delete (client-side stack in `editorStore`;
  a save checkpoint is pushed onto the stack on successful save so undo can
  revert past the last save, and the stack is reset only when the route is
  closed or a new route is loaded)
- Edit track metadata (name, description, estimated speed)
- Live distance and estimated duration preview in the editor, computed locally in
  `editorStore` as points are added or moved (does not require a save)
- Elevation profile chart below the map (with visual indication of missing/partial data)
- Route statistics displayed (distance, elevation gain, estimated duration — marked
  partial if elevation coverage is incomplete; elevation gain and duration update
  only after save, distance updates live)
- Place name search (Kartverket Stedsnavn API) to navigate the map
- Download track as GPX

### Frontend state management
- **React Query (TanStack Query)** — manages async server state (e.g. data fetching,
  caching, loading flags, invalidations) for `routes` CRUD actions and `auth` requests.
- **Zustand (`authStore`)** — tracks synchronous frontend session presence.
- **Zustand (`editorStore`)** — highly synchronous client editor state, active route
  points, map interaction mode, un-saved/dirty flags, and undo/redo history stacks.

### Frontend non-functional requirements
- Accessibility baseline for the first edition:
  - Keyboard-accessible primary actions (save, undo/redo, delete selected point,
    import/export controls).
  - Visible focus states and minimum WCAG AA contrast for UI controls and text.
  - Form controls and dialogs include proper labels/ARIA semantics.
  - Elevation chart and partial-data indicators provide non-color cues (icons/text)
    so information is not color-dependent.
- Browser/device support baseline:
  - Latest two stable versions of Chrome, Firefox, Safari, and Edge.
  - Responsive support for desktop and tablet; mobile supports route viewing and
    light edits, while dense point editing is desktop-first in the first edition.

### Future functionality candidates
- Trim routes
- Split routes
- Merge routes

### Performance notes
- Imported GPX files may contain many thousands of points. The frontend should be
  prepared to simplify rendered geometry for interaction while preserving the
  stored source geometry.
- The editor maintains two geometry representations for large routes: full-
  resolution source points for save/export/statistics, and a simplified render
  geometry for map drawing/interactions.
- Large routes must not render draggable handles for every point at once. The
  first edition uses
  progressive editing affordances (e.g. selected-point handles, viewport/zoom-
  scoped handles, or edit-mode subsets) so the map remains responsive.
- The backend should validate point count and file size on import to avoid slow
  or abusive uploads (suggested limits: max 10MB file size, max 50,000 points per track).

### Delivery priority
- Core first-edition scope is: authentication, dashboard route list, GPX import,
  route editor, manual save, and GPX export.
- If delivery risk or schedule pressure rises, the first deferrable features are:
  `/settings`, orthophoto toggle, and place-name search.
- If Stedsnavn place search is deferred, the editor must provide a "Go to
  coordinates" input (lat/lon) so users can navigate to a specific area without
  manually panning across the entire map.

### Implementation phases (TDD-aligned)
- Phase 1: Backend calculation units and auth/route API contract tests first,
  then minimal implementation.
- Phase 2: Backend save/import pipeline tests (replace-all points, elevation
  enrichment, GPX edge cases/limits), then implementation.
- Phase 3: Frontend store/unit tests for `editorStore` and auth/session edge
  handling (`401` re-auth flow, `409` conflict flow), then implementation.
- Phase 4: Frontend component/integration tests for dashboard/editor flows,
  statistics display, accessibility baseline, and tile/error states, then
  implementation.
- Phase 5: Cross-stack contract fixtures to verify frontend/backend parity for
  distance and elevation-threshold behavior.
- Phase 6: Manual verification of Kartverket integrations and GPX round-trip
  before release.
- Detailed test cases and exact execution order are defined in
  `plan/TEST_PLAN.md` and act as phase-level quality gates.

---

## Kartverket Integrations

| Service              | Usage                                  |
|----------------------|----------------------------------------|
| WMTS topo (`topo`)   | Base map layer in Leaflet              |
| WMTS orthophoto (`nib`) | Alternative base layer toggle       |
| Høydedata API        | Fetch elevation for drawn/imported points |
| Stedsnavn API        | Place name search in the map UI        |

All map data is sourced exclusively from Kartverket (Norwegian Mapping Authority).

### Map Tile Endpoints (Leaflet Setup)
For integrating with `react-leaflet` using standard XYZ `TileLayer` components, use the following public Kartverket cache URLs (Webmercator projection is supported natively by Leaflet):
- **Topo**: `https://cache.kartverket.no/topo/v1/wmts/1.0.0/topo/default/webmercator/{z}/{y}/{x}.png`
- **Orthophoto (nib)**: `https://cache.kartverket.no/nib/v1/wmts/1.0.0/nib/default/webmercator/{z}/{y}/{x}.png`

*(Note: These should be configured via the frontend `.env` to make them easily adjustable if the APIs evolve).*

### Attribution and compliance
- Kartverket data is licensed under CC BY 4.0 / Norge digitalt. The application
  must display proper attribution on the map (e.g. "© Kartverket").
- Verify any rate limits or usage terms for the Høydedata and Stedsnavn APIs
  before launch.
- No API key is required for Kartverket WMTS tiles, but fair-use policies apply.
- Kartverket's Stedsnavn REST API does not require registration and can be used
  directly from the documented public endpoint.
- Høydedata/terrengdata is generally available through public API and download
  services, but some datasets/services on `hoydedata.no` are restricted to
  Norge digitalt users. The exact elevation lookup service used by the backend
  must therefore be verified in Geonorge before implementation, rather than
  assuming every terrain-related endpoint is unrestricted.
- If Kartverket WMTS tiles fail to load, the map should display a visible
  "Map tiles unavailable — check your connection" overlay rather than a blank
  canvas. No fallback tile provider in the first edition (all map data is
  Kartverket-only), but the error state must be explicit.

### Access requirements for planned Kartverket integrations
- WMTS topo and orthophoto tile services are public and require no API key or
  registration for normal use.
- Stedsnavn place-name search is public and requires no API key or registration.
- The backend elevation integration must use a specifically verified public
  elevation endpoint/product. If the preferred service turns out to require
  Norge digitalt access or other approval, elevation enrichment should be
  replaced with a verified open alternative before implementation.

---

## Development Environment

- **Postgres** — Docker container, exposed on `localhost:5432`
- **FastAPI**  — run locally with `uvicorn`, hot reload enabled
- **React**    — run locally with `vite`, API calls proxied to FastAPI
- **Alembic**  — manage DB schema migrations

### Quick start (local dev)
```bash
# Start Postgres
docker run --name gpxedit-db -e POSTGRES_PASSWORD=secret -e POSTGRES_DB=gpxedit -p 5432:5432 -d postgres:18.3

# Backend
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
alembic upgrade head
uvicorn main:app --reload

# Frontend
cd frontend
npm install
npm run dev
```

### Environment configuration
- Backend uses a `.env` file for runtime settings such as `DATABASE_URL`,
  `JWT_SECRET_KEY`, `JWT_EXPIRES_MINUTES`, and Kartverket API base URLs.
- Frontend uses a `.env` file for API base URL and public map configuration.
- Secrets are never committed to git. Provide a checked-in `.env.example` for
  developer onboarding.

### Privacy and data lifecycle
- User data lifecycle is explicit: users can delete their account, which cascades
  deletion of owned routes/points (`ON DELETE CASCADE`).
- Production logging must avoid sensitive payload capture (passwords, raw auth
  tokens, full JWTs, and full GPX file contents).
- Data export requests (user-owned routes and profile metadata) and account
  deletion requests are handled through authenticated endpoints and auditable log
  events.
- Retention windows for auth/security logs and deleted-account tombstones are
  documented per environment and reviewed before launch.

### Database migration and data safety strategy
- All schema changes are delivered through Alembic migrations; direct manual DB
  schema edits are not allowed.
- For non-trivial migrations, use expand/contract sequencing where possible:
  additive change -> dual-write/read compatibility window -> cleanup migration.
- Data backfills run as explicit, resumable scripts/migrations with progress
  logging and idempotent behavior.
- Pre-deploy backup (or verified snapshot) is required before production
  migrations; rollback means roll-forward with a corrective migration unless a
  full restore is explicitly required.

### Deployment and environments
- Environments: local, staging, production with separate databases, secrets, and
  Kartverket API configuration.
- CI runs lint + tests for backend/frontend on every PR; deployment requires CI
  green status.
- Staging deploy is required before production for schema or auth-flow changes.
- Production secrets are managed in the deploy platform secret store (never in
  repo or plaintext env files).
- Dependency vulnerability scanning (backend/frontend) and container image
  scanning run in CI with a defined triage SLA for high/critical findings.
- Secret rotation cadence (JWT signing secret, DB credentials, SMTP/API secrets)
  has an owner, schedule, and runbook per environment.
- Release notes should include any migration steps and feature flags/toggles if
  used.

### Scope vs environment definitions
- `first edition` means feature scope/contract, not environment. The first
  edition scope is expected to run in production after passing staging and
  release checks.
- `local`, `staging`, and `production` are deployment environments that exist for
  the same version line (including the first edition).
- Statements marked "in the first edition" are mandatory for the first
  production release unless they are explicitly marked as out of scope.
- Statements marked "future functionality" are intentionally excluded from the
  first edition across all environments (including production), not just
  postponed in development.

### Backup and restore expectations
- Production Postgres uses scheduled automated backups with a documented
  retention policy.
- At least one periodic restore drill is executed in a non-production
  environment to verify backups are usable.
- Recovery objectives (target RPO/RTO) are documented and reviewed before launch.

---

## Testing Strategy

- Backend API tests using `pytest` and `httpx` for auth, route CRUD, GPX import, and GPX export round-trip.
- Unit tests for distance, elevation gain, and estimated duration calculations.
- GPX edge-case fixtures: empty file, malformed XML, multi-segment import, missing
  elevations, and point counts at/above the import limit.
- Frontend tests using `Vitest` and `React Testing Library` for dashboard flows and
  core editor behaviors such as adding, moving, and deleting route points, and
  undo/redo behavior.
- Integration tests for the elevation enrichment pipeline using mocked Kartverket
  Høydedata responses, covering: full enrichment, partial failure/timeout,
  sampling at the cap boundary, and correct `elevation_is_partial` / coverage
  ratio computation.
- Manual verification against Kartverket map tiles, place search, and elevation
  lookups during development.
- See `plan/TEST_PLAN.md` for the full first-edition TDD test matrix, API/store
  contract cases, and execution order.

---

## Observability
- Backend uses structured JSON logging (e.g. `structlog` or Python `logging`
  with JSON formatter) for API errors, failed/timed-out elevation lookups,
  import failures, and auth events.
- No external log aggregation in the first edition — logs go to stdout for local
  development and container-level capture.
- Minimal first-edition metrics are required (via app metrics endpoint or
  platform metrics):
  request latency, error rate, save duration, GPX import duration/failure rate,
  elevation enrichment timeout/partial rate, and auth/login failure rate.
- Basic alerts should be configured for sustained 5xx spikes, unusually high
  save/import failures, and elevation service timeout bursts.

---

## Future functionality (out of scope for first edition)
- Snap to road/trail (depends on routing data availability from Kartverket)
- Share routes with other users (public links or user-to-user)
- OAuth login (Google, GitHub etc.)
- Timestamps per point for unedited recorded tracks
- Incremental point-edit APIs instead of full route point replacement
