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
from .jolpica import JolpicaError, _get, base_url, fetch_pages, max_round
from .state import Watermark, needs_load, progress_name, write_watermark
from .warehouse import ensure_table, replace_race, replace_season

log = logging.getLogger(__name__)


def latest_completed_race(
    *, transport: Callable[[str], object], url_base: str | None = None
) -> tuple[int, int]:
    """Season and round of the most recently completed race.

    One request, and the only thing the scheduled run needs in order to decide
    it has nothing to do.
    """
    url = f"{(url_base or base_url()).rstrip('/')}/current/last/results/?limit=1"
    response = _get(url, transport=transport, sleep=time.sleep)
    race = json.loads(response.text)["MRData"]["RaceTable"]["Races"][0]
    return int(race["season"]), int(race["round"])


def season_rounds(
    season: int,
    *,
    transport: Callable[[str], object],
    sleep: Callable[[float], None] = time.sleep,
    url_base: str | None = None,
) -> list[int]:
    """Every round on a season's calendar, including races not yet run.

    One request: no season has more than 100 races.
    """
    url = f"{(url_base or base_url()).rstrip('/')}/{season}/races/?limit=100"
    response = _get(url, transport=transport, sleep=sleep)
    races = json.loads(response.text)["MRData"]["RaceTable"]["Races"]
    return sorted(int(race["round"]) for race in races)


def load_season(
    cursor,
    schema: str,
    endpoint: Endpoint,
    season: int,
    *,
    transport: Callable[[str], object],
    sleep: Callable[[float], None] = time.sleep,
    url_base: str | None = None,
    as_of_round: int | None = None,
) -> Watermark:
    """Fetch and land every page of one endpoint for one season.

    `as_of_round` is the latest completed round in that season at the moment of
    loading, supplied for the current season. It is what gets watermarked, in
    preference to whatever rounds happen to appear in the payload: `drivers`
    has no rounds at all and `races` lists rounds that have not been run yet,
    so payload-derived rounds cannot answer "is this load still current?".

    Raises rather than watermarking if the fetch fails, so the season stays
    unloaded and a re-run resumes it.
    """
    table = f"{schema}.{endpoint.table}"
    pages = list(
        fetch_pages(
            endpoint.path, season, transport=transport, sleep=sleep, url_base=url_base
        )
    )

    ensure_table(cursor, table, ddl.PAGE_DDL)
    replace_season(cursor, table, season, pages)

    if as_of_round is None:
        rounds = [r for r in (max_round(page.payload) for page in pages) if r is not None]
        as_of_round = max(rounds) if rounds else None

    return Watermark(
        endpoint=endpoint.name,
        season=season,
        last_round=as_of_round,
        total_rows=pages[0].total if pages else 0,
    )


def load_races(
    cursor,
    schema: str,
    endpoint: Endpoint,
    season: int,
    *,
    rounds: list[int],
    watermarks: dict[tuple[str, int], Watermark],
    state_table: str,
    transport: Callable[[str], object],
    sleep: Callable[[float], None] = time.sleep,
    url_base: str | None = None,
    latest_round: int | None = None,
    force: bool = False,
) -> Watermark | None:
    """Load a per-race endpoint race by race, from the first race not yet loaded.

    Progress is watermarked after every race, so a run that fails or is stopped
    part-way through a season resumes at the next race. The endpoint's own
    watermark is written only once the season is loaded as far as it can be,
    and is what's returned; None means the season isn't complete yet.

    `latest_round` caps the current season at the races actually run. If the
    newest of those returns nothing, its data isn't published yet: the load
    stops without marking it, so the next run tries again. An empty race in a
    past season is simply absence.
    """
    progress_key = (progress_name(endpoint.name), season)
    completed = watermarks.get((endpoint.name, season))
    progress = watermarks.get(progress_key)

    if force:
        loaded_through, total_rows = 0, 0
    else:
        loaded_through = max(
            (w.last_round or 0 for w in (completed, progress) if w is not None), default=0
        )
        total_rows = progress.total_rows if progress else 0

    if latest_round is not None:
        rounds = [r for r in rounds if r <= latest_round]

    table = f"{schema}.{endpoint.table}"
    ensure_table(cursor, table, ddl.RACE_PAGE_DDL)

    for round_number in rounds:
        if round_number <= loaded_through:
            continue

        pages = list(
            fetch_pages(
                endpoint.path, season, round_number=round_number,
                transport=transport, sleep=sleep, url_base=url_base,
            )
        )

        if not pages and latest_round is not None and round_number == rounds[-1]:
            log.info(
                "%s %s round %s: nothing published yet, will retry next run",
                season, endpoint.name, round_number,
            )
            return None

        replace_race(cursor, table, season, round_number, pages)
        total_rows += pages[0].total if pages else 0

        step = Watermark(progress_key[0], season, last_round=round_number, total_rows=total_rows)
        write_watermark(cursor, state_table, step)
        watermarks[progress_key] = step
        log.debug("%s %s round %s: %d rows", season, endpoint.name, round_number, step.total_rows)

    last_round = latest_round if latest_round is not None else (rounds[-1] if rounds else None)
    return Watermark(endpoint.name, season, last_round=last_round, total_rows=total_rows)


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
    endpoints: Iterable[Endpoint] | None = None,
) -> tuple[list[Watermark], list[str]]:
    """Load every endpoint covering every season, skipping what is current.

    One failing endpoint must not sink a long backfill, so failures are
    collected and reported at the end rather than raised.

    `endpoints` restricts the run to those endpoints; by default, all of them.
    """
    latest_round_by_season = latest_round_by_season or {}
    state_table = f"{schema}.{ddl.LOAD_STATE_TABLE}"
    ensure_table(cursor, state_table, ddl.LOAD_STATE_DDL)
    only = tuple(endpoints) if endpoints is not None else None

    loaded: list[Watermark] = []
    failures: list[str] = []

    for season in seasons:
        season_endpoints = (
            covering(season) if only is None else tuple(e for e in only if e.covers(season))
        )
        latest_round = latest_round_by_season.get(season)
        calendar: list[int] | None = None

        for endpoint in season_endpoints:
            if not needs_load(
                endpoint.name, season, watermarks, latest_round=latest_round, force=force,
            ):
                log.debug("%s %s: up to date", season, endpoint.name)
                continue

            try:
                if endpoint.per_race:
                    if calendar is None:
                        calendar = season_rounds(
                            season, transport=transport, sleep=sleep, url_base=url_base
                        )
                    watermark = load_races(
                        cursor, schema, endpoint, season,
                        rounds=calendar, watermarks=watermarks, state_table=state_table,
                        transport=transport, sleep=sleep, url_base=url_base,
                        latest_round=latest_round, force=force,
                    )
                    if watermark is None:
                        continue
                else:
                    watermark = load_season(
                        cursor, schema, endpoint, season,
                        transport=transport, sleep=sleep, url_base=url_base,
                        as_of_round=latest_round,
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
