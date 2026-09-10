# F1 Data Hub — scaffold and Phase 1 ingestion

**Date:** 2026-09-10
**Status:** Approved
**Scope:** Repository scaffold plus Phase 1 (Jolpica API → Databricks raw layer).
Phases 2 (dbt models) and 3 (Actions + Power BI) are out of scope here.

## Why this project exists

Built in response to interview feedback on a GitHub review: show *why*
architectural layers exist rather than just using the tools, and move off
static CSVs onto a live, API-driven pipeline. Every decision below is
judged against that goal.

## Source contract (verified 2026-09-10)

Base URL `https://api.jolpi.ca/ergast/f1`. Ergast shut down in 2024; Jolpica
is the backwards-compatible successor.

- Responses wrap everything in an `MRData` envelope carrying `limit`,
  `offset` and `total`.
- 77 seasons available (1950–2026). Current season is 2026; latest completed
  round at time of writing is 13 (Italian Grand Prix, 2026-09-06).
- `limit` hard-caps at 100. Requesting 200 silently returns 100.
- **Pagination is over result rows, not races.** `/2024/results/?limit=100`
  returns 100 result rows spanning 6 races, so one page straddles round
  boundaries. This is the single most important fact in this document: the
  raw layer cannot be keyed by round.
- Qualifying data begins in 1994. Sprint data begins in 2021.
- No rate-limit headers are exposed. Documented anonymous budget is roughly
  4 requests/second burst, 500/hour sustained.

## Decisions

| Decision | Choice | Why |
| --- | --- | --- |
| Raw storage | Delta table with verbatim JSON in a `payload` column | Keeps the pipeline on the SQL-warehouse path — same auth scope and driver as the sibling Passive-Investing-Hub project — while still giving a genuinely untouched raw layer. Staging becomes "parse + cast", a stronger demonstration of layering than "rename only". Rejected: Unity Catalog Volumes (Files API upload plus serverless `read_files` is more moving parts on Free Edition, and harder to unit test); typed relational raw tables (drops the untouched property and hides parsing in Python where dbt cannot test or document it). |
| Table granularity | One raw table per endpoint | dbt sources then map 1:1 to staging models, which is precisely the "staging = clean source atoms" answer the layering question calls for. |
| Raw grain | One row per API page | Forced by row-based pagination. Keyed by `(season, page_offset)`. |
| Re-fetch semantics | Delete all rows for a season, then insert every page fetched | A partial mix of stale and fresh pages is never observable. Safe to re-run. |
| Idempotency | Separate `raw_jolpica_load_state` watermark table | Control state stays distinct from data. Deciding whether to run must not require parsing payload JSON in SQL. |
| History | All seasons from 1950 | Richest marts. Costs a long first load, handled by resumability below. |
| Endpoints | `races`, `results`, `qualifying`, `drivers` | Exactly the four staging models Phase 2 names. Sprint omitted as YAGNI; adding one is a single entry in the registry. |
| Rate limiting | ~3 req/s throttle, exponential backoff honouring `Retry-After`, resumable | ~585 requests for a full backfill against a ~500/hour budget, so hitting the cap is expected. Seasons already in the watermark table are skipped, making a re-run the recovery path. |

## Components

- `ingestion/config.py` — environment plus `dbt_project.yml` vars, so
  ingestion and dbt can never disagree about coverage.
- `ingestion/jolpica.py` — HTTP client: pagination, throttle, retry. Takes an
  injected transport so tests need no network.
- `ingestion/endpoints.py` — registry of endpoints and their season coverage.
- `ingestion/ddl.py` — explicit raw DDL, so a schema change is a visible diff.
- `ingestion/state.py` — watermark reads/writes and the skip-or-load decision.
- `ingestion/warehouse.py` — Databricks SQL writes with bound parameters.
- `ingestion/__main__.py` — CLI: `backfill` and `incremental`.

## Data flow

`backfill`: for each season 1950..current, for each endpoint covering that
season, skip if watermarked (unless `--force`); else page through the API,
delete the season's rows, insert every page, write the watermark.

`incremental`: one call to `/current/last/results` yields the latest completed
round. If it matches the watermark, exit without writing. Otherwise reload the
current season for every endpoint.

## Error handling

- 429 and 5xx: exponential backoff honouring `Retry-After`, then give up with
  the season unwatermarked so a re-run retries it.
- A season with no data for an endpoint (qualifying before 1994) is recorded
  as a zero-row load, not an error.
- One failing endpoint must not sink the whole backfill; failures are
  collected and reported at the end with a non-zero exit.

## Testing

Network and warehouse are injected, so all logic is unit-tested offline
against recorded fixtures in `tests/fixtures/jolpica/`:

- pagination terminates at `total` and respects the 100 cap
- a page straddling rounds is stored verbatim, not split
- 429 backoff retries and eventually gives up
- watermark comparison picks skip vs load
- parameter binding handles nulls and numpy scalars

`dbt deps` and `dbt parse` must pass with no credentials. The live backfill is
run by the repository owner once `.env` is populated; it is not verified here.

## Out of scope

dbt models beyond the sources file, GitHub Actions workflows, Power BI, and
the sprint endpoint.
