"""Orchestration: decide what to load, load it, record what happened.

Kept separate from the CLI so the decisions are testable without argument
parsing, and separate from the warehouse and API modules so neither of those
has to know why it is being called.
"""

from __future__ import annotations

import json
import logging
import time
from collections.abc import Callable, Iterable

from . import ddl
from .endpoints import Endpoint, covering
from .jolpica import JolpicaError, base_url, fetch_pages, max_round
from .state import Watermark, needs_load, write_watermark
from .warehouse import ensure_table, replace_season

log = logging.getLogger(__name__)


def latest_completed_race(
    *, transport: Callable[[str], object], url_base: str | None = None
) -> tuple[int, int]:
    """Season and round of the most recently completed race.

    One request, and the only thing the scheduled run needs in order to decide
    it has nothing to do.
    """
    from .jolpica import _get

    url = f"{(url_base or base_url()).rstrip('/')}/current/last/results/?limit=1"
    response = _get(url, transport=transport, sleep=time.sleep)
    race = json.loads(response.text)["MRData"]["RaceTable"]["Races"][0]
    return int(race["season"]), int(race["round"])


def load_season(
    cursor,
    schema: str,
    endpoint: Endpoint,
    season: int,
    *,
    transport: Callable[[str], object],
    sleep: Callable[[float], None] = time.sleep,
    url_base: str | None = None,
) -> Watermark:
    """Fetch and land every page of one endpoint for one season.

    Raises rather than watermarking if the fetch fails, so the season stays
    unloaded and a re-run resumes it.
    """
    table = f"{schema}.{endpoint.table}"
    pages = list(
        fetch_pages(
            endpoint.name, season, transport=transport, sleep=sleep, url_base=url_base
        )
    )

    ensure_table(cursor, table, ddl.PAGE_DDL)
    replace_season(cursor, table, season, pages)

    rounds = [r for r in (max_round(page.payload) for page in pages) if r is not None]
    return Watermark(
        endpoint=endpoint.name,
        season=season,
        last_round=max(rounds) if rounds else None,
        total_rows=pages[0].total if pages else 0,
    )


def run_seasons(
    cursor,
    schema: str,
    seasons: Iterable[int],
    *,
    watermarks: dict[tuple[str, int], Watermark],
    transport: Callable[[str], object],
    sleep: Callable[[float], None] = time.sleep,
    latest_round_by_season: dict[int, int] | None = None,
    force: bool = False,
    url_base: str | None = None,
) -> tuple[list[Watermark], list[str]]:
    """Load every endpoint covering every season, skipping what is current.

    One failing endpoint must not sink a 585-request backfill, so failures are
    collected and reported at the end rather than raised.
    """
    latest_round_by_season = latest_round_by_season or {}
    state_table = f"{schema}.{ddl.LOAD_STATE_TABLE}"
    ensure_table(cursor, state_table, ddl.LOAD_STATE_DDL)

    loaded: list[Watermark] = []
    failures: list[str] = []

    for season in seasons:
        for endpoint in covering(season):
            if not needs_load(
                endpoint.name,
                season,
                watermarks,
                latest_round=latest_round_by_season.get(season),
                force=force,
            ):
                log.debug("%s %s: up to date", season, endpoint.name)
                continue

            try:
                watermark = load_season(
                    cursor, schema, endpoint, season,
                    transport=transport, sleep=sleep, url_base=url_base,
                )
            except JolpicaError as exc:
                log.error("%s %s: FAILED -- %s", season, endpoint.name, exc)
                failures.append(f"{season} {endpoint.name}: {exc}")
                continue

            write_watermark(cursor, state_table, watermark)
            watermarks[(endpoint.name, season)] = watermark
            loaded.append(watermark)
            log.info(
                "%s %s: %d rows%s",
                season, endpoint.name, watermark.total_rows,
                f" through round {watermark.last_round}" if watermark.last_round else "",
            )

    return loaded, failures
