"""Ingestion watermarks -- control state, kept separate from data.

Deciding whether there is anything to do must not require parsing payload JSON
in SQL, so what has been loaded is recorded explicitly in its own small table.
That separation is also what makes a rate-limited backfill resumable: a season
that failed was never watermarked, so re-running picks it straight back up.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass


@dataclass(frozen=True)
class Watermark:
    endpoint: str
    season: int
    last_round: int | None
    total_rows: int


def read_watermarks(
    cursor, table: str, *, missing_ok: bool = False
) -> dict[tuple[str, int], Watermark]:
    """Every recorded load, keyed by (endpoint, season).

    `missing_ok` treats an unreadable table as "nothing loaded yet". It exists
    for `--dry-run`, which must not create the table just to look at it. A real
    run creates the table first, so there a failure to read it is genuine.
    """
    try:
        cursor.execute(f"SELECT endpoint, season, last_round, total_rows FROM {table}")
    except Exception:
        if missing_ok:
            return {}
        raise
    return {
        (endpoint, int(season)): Watermark(
            endpoint=endpoint,
            season=int(season),
            last_round=None if last_round is None else int(last_round),
            total_rows=int(total_rows),
        )
        for endpoint, season, last_round, total_rows in cursor.fetchall()
    }


def needs_load(
    endpoint: str,
    season: int,
    watermarks: dict[tuple[str, int], Watermark],
    *,
    latest_round: int | None = None,
    force: bool = False,
) -> bool:
    """Whether `(endpoint, season)` should be fetched.

    `latest_round` is the newest completed round the API reports, supplied only
    for the current season. Completed seasons never change, so once loaded they
    are skipped outright.
    """
    if force:
        return True

    existing = watermarks.get((endpoint, season))
    if existing is None:
        return True

    if latest_round is None:
        return False

    return existing.last_round is None or latest_round > existing.last_round


def write_watermark(cursor, table: str, watermark: Watermark) -> None:
    """Replace the watermark for one (endpoint, season).

    Delete-then-insert rather than MERGE: it is two obvious statements, and the
    table is small enough that nothing is gained by being cleverer.
    """
    cursor.execute(
        f"DELETE FROM {table} WHERE endpoint = ? AND season = ?",
        [watermark.endpoint, watermark.season],
    )
    cursor.execute(
        f"INSERT INTO {table} (endpoint, season, last_round, total_rows, loaded_at) "
        "VALUES (?, ?, ?, ?, ?)",
        [
            watermark.endpoint,
            watermark.season,
            watermark.last_round,
            watermark.total_rows,
            dt.datetime.now(dt.UTC),
        ],
    )
