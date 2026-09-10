# F1 Data Hub

An ELT pipeline and Power BI dashboard for Formula 1 race data.

Jolpica API → Databricks raw layer → dbt (staging → intermediate → marts) →
Power BI, running automatically via scheduled GitHub Actions.

## Why the layers exist

This project exists to answer a specific question: *why* does a warehouse need
architectural layers, rather than one script that pulls an API into a table a
dashboard reads?

Each layer has one job, and the boundary between them is where the useful
guarantees live:

| Layer | Job | Guarantee it provides |
| --- | --- | --- |
| **Raw** | Store the API response byte-for-byte | You can rebuild every downstream table without re-requesting the API. A parsing bug is fixable retroactively because the source is still here. |
| **Staging** | Parse and cast, 1:1 with a source | One place per source where "what the API calls it" becomes "what we call it". Nothing joins here, so a source change touches exactly one model. |
| **Intermediate** | Business logic — joins, pivots, rolling windows | Logic used by more than one mart lives once, and is testable on its own. |
| **Marts** | Wide, denormalized tables the dashboard queries | The BI tool never joins, so a dashboard change never becomes a modelling change. |

The raw layer is what makes the rest safe to get wrong. Everything from
staging down can be dropped and rebuilt from data already on disk.

## Status

**Phase 1 — ingestion. Complete.** Jolpica pages land in the raw layer, with a
resumable backfill and a scheduled-run idempotency check.

Phase 2 (dbt models) and Phase 3 (GitHub Actions + Power BI) are not started.
The dbt project is scaffolded and its sources are declared; no models yet.

## Setup

Requires Python 3.11–3.13 and [uv](https://docs.astral.sh/uv/).

```bash
uv sync
```

This creates a project-local `.venv` with `dbt-databricks`. It deliberately
does not touch any global dbt install.

### Connect to Databricks

1. Copy `.env.example` to `.env` if it is not already there.
2. Uncomment the three credential lines and fill them in from your workspace:
   - **Host** and **HTTP path** — SQL Warehouses → your warehouse →
     Connection details
   - **Token** — Settings → Developer → Access tokens → Generate new token
3. Confirm the connection:

```bash
uv run dbt debug
```

dbt auto-loads `.env` from the project directory, so no shell setup is needed
and no `--project-dir` / `--profiles-dir` flags are required — those paths are
set in `.env` too.

`.env` is gitignored. `dbt_project/profiles.yml` is committed but holds no
secrets; it reads everything from the environment.

> **Do not leave a credential line uncommented but empty.** `DATABRICKS_TOKEN=`
> sets the variable to an empty string instead of leaving it unset, which
> defeats the offline placeholder defaults in `profiles.yml`. dbt then fails
> with `cannot configure default credentials ... auth_type=external-browser`,
> which does not mention the real problem. Fill the line in or leave it
> commented.

## Ingestion

```bash
uv run python -m ingestion backfill --dry-run       # show the plan, write nothing
uv run python -m ingestion backfill                 # all seasons, 1950 onwards
uv run python -m ingestion backfill --seasons 2020-2026
uv run python -m ingestion incremental              # current season, if a race has run
```

**The first backfill takes a while.** All 77 seasons is roughly 585 requests
against Jolpica's ~500/hour anonymous budget, so expect to hit the rate limit.
That is designed for: a season is only watermarked once it has loaded
successfully, so re-running `backfill` resumes where it stopped. Start with
`--dry-run` to see the plan, and consider working through it in chunks with
`--seasons`.

`incremental` is the scheduled path. It costs one API call to find the latest
completed race and exits without writing if the raw layer already has it.

## What the raw layer looks like

One table per endpoint, one row per **API page**:

```
season | page_offset | page_limit | total_rows | request_url | payload | ingested_at
```

`payload` is the response body exactly as it arrived.

Jolpica paginates over **result rows, not races** — `/2024/results/?limit=100`
returns 100 result rows spanning six races — so a page routinely straddles
round boundaries. That is why the grain is `(season, page_offset)` and not
`(season, round)`, and why nothing before the staging layer tries to split a
page along race lines.

Re-fetching a season deletes its pages and reinserts them, so a partial mix of
stale and fresh pages is never observable.

`raw_jolpica_load_state` holds ingestion watermarks. It is control state, not
data: keeping it separate means deciding whether to run never requires parsing
payload JSON in SQL.

### Source coverage

| Endpoint | Seasons |
| --- | --- |
| `races`, `results`, `drivers` | 1950 onwards |
| `qualifying` | 1994 onwards |

A season an endpoint has no data for is recorded as a zero-row load, not an
error, so it is not retried on every subsequent run.

## Tests

```bash
uv run pytest
uv run ruff check .
```

All 40 tests run offline against real Jolpica responses recorded under
`tests/fixtures/jolpica/`. The HTTP transport and the database cursor are both
injected, so pagination, backoff, watermarking and parameter binding are
verified without a network or a warehouse.

`uv run dbt deps` and `uv run dbt parse` also work with no credentials.

## Design notes

`docs/superpowers/specs/` holds the design decisions and the verified details
of the Jolpica contract that drove them.
