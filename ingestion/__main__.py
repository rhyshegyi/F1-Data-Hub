"""CLI for the ingestion layer.

    uv run python -m ingestion backfill              # every season, resumable
    uv run python -m ingestion backfill --seasons 2020-2026
    uv run python -m ingestion backfill --dry-run    # show the plan, write nothing
    uv run python -m ingestion incremental           # current season, if a race has run

`backfill` is safe to re-run: seasons already recorded in the load-state table
are skipped, so hitting Jolpica's hourly cap just means running it again.
"""

from __future__ import annotations

import argparse
import logging
import sys

import requests

from . import ddl
from .config import databricks_config, first_season
from .endpoints import covering
from .pipeline import latest_completed_race, run_seasons
from .state import needs_load, read_watermarks
from .warehouse import connect, ensure_schema, ensure_table

log = logging.getLogger("ingestion")

REQUEST_TIMEOUT = 30


def make_transport():
    """A pooled requests session, shaped the way fetch_pages expects."""
    session = requests.Session()
    session.headers["User-Agent"] = "f1-data-hub/0.1 (+https://github.com/rhys-hegyi)"
    return lambda url: session.get(url, timeout=REQUEST_TIMEOUT)


def parse_seasons(spec: str | None, current_season: int) -> list[int]:
    """Parse `1950-2026`, `2024`, or None meaning every season.

    Invalid specs raise rather than resolving to an empty list: a backfill that
    silently does nothing looks identical to one that had nothing to do.
    """
    if not spec:
        return list(range(first_season(), current_season + 1))

    try:
        if "-" in spec:
            start, end = (int(part) for part in spec.split("-", 1))
        else:
            start = end = int(spec)
    except ValueError:
        raise ValueError(
            f"Could not read {spec!r} as a season or season range (e.g. 2024 or 2020-2026)"
        ) from None

    if end < start:
        raise ValueError(f"Season range {spec!r} ends before it starts")

    return list(range(start, end + 1))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ingestion")
    subparsers = parser.add_subparsers(dest="command", required=True)

    backfill = subparsers.add_parser("backfill", help="load historical seasons")
    backfill.add_argument("--seasons", help="e.g. 2020-2026 or 2024; default all")
    backfill.add_argument("--force", action="store_true", help="reload seasons already loaded")
    backfill.add_argument("--dry-run", action="store_true", help="show the plan, write nothing")

    subparsers.add_parser("incremental", help="load the current season if a new race has run")

    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s  %(levelname)-7s %(message)s",
        datefmt="%H:%M:%S",
    )
    # The Thrift driver logs every HTTP round trip at INFO, which buries ours.
    for noisy in ("databricks", "thrift", "urllib3", "requests"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    transport = make_transport()
    config = databricks_config()
    schema = f"{config.catalog}.{config.raw_schema}"

    current_season, current_round = latest_completed_race(transport=transport)
    log.info("Latest completed race: %s round %s", current_season, current_round)

    with connect(config) as connection, connection.cursor() as cursor:
        ensure_schema(cursor, config.catalog, config.raw_schema)
        state_table = f"{schema}.{ddl.LOAD_STATE_TABLE}"
        ensure_table(cursor, state_table, ddl.LOAD_STATE_DDL)
        watermarks = read_watermarks(cursor, state_table)

        if args.command == "incremental":
            seasons = [current_season]
            force = False
        else:
            seasons = parse_seasons(args.seasons, current_season)
            force = args.force

        # Only the current season can gain rows; earlier seasons are settled.
        latest_round_by_season = {current_season: current_round}

        if args.command == "backfill" and args.dry_run:
            return _report_plan(seasons, watermarks, latest_round_by_season, force)

        loaded, failures = run_seasons(
            cursor, schema, seasons,
            watermarks=watermarks,
            transport=transport,
            latest_round_by_season=latest_round_by_season,
            force=force,
        )

    if not loaded and not failures:
        log.info("Nothing to do -- raw layer is up to date")

    total_rows = sum(w.total_rows for w in loaded)
    log.info("Loaded %d endpoint-seasons (%d source rows)", len(loaded), total_rows)

    if failures:
        log.warning("%d failure(s):", len(failures))
        for failure in failures:
            log.warning("  %s", failure)
        return 1

    return 0


def _report_plan(seasons, watermarks, latest_round_by_season, force) -> int:
    """Print what a real run would fetch, using the same decision function."""
    planned = [
        (season, endpoint.name)
        for season in seasons
        for endpoint in covering(season)
        if needs_load(
            endpoint.name, season, watermarks,
            latest_round=latest_round_by_season.get(season), force=force,
        )
    ]
    for season, name in planned:
        log.info("would load %s %s", season, name)
    log.info("%d endpoint-season(s) to load, nothing written", len(planned))
    return 0


if __name__ == "__main__":
    sys.exit(main())
