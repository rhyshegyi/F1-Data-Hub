"""Databricks writes for the raw layer.

Everything goes through the SQL warehouse rather than Unity Catalog Volumes.
The payload column holds the response body verbatim, so the raw layer is still
genuinely untouched, while the access token stays inside the narrow BI Tools
scope and the whole path stays unit-testable behind an injected cursor.
"""

from __future__ import annotations

import datetime as dt
import logging
from collections.abc import Iterable, Sequence
from contextlib import contextmanager

from .config import DatabricksConfig, databricks_config
from .jolpica import Page

log = logging.getLogger(__name__)

# Pages are large -- a full results page is roughly 90KB of JSON -- so this is
# deliberately far smaller than a typical row batch. Five pages is about 450KB
# per statement, which the warehouse accepts comfortably.
INSERT_BATCH_SIZE = 5

PAGE_COLUMNS = (
    "season",
    "page_offset",
    "page_limit",
    "total_rows",
    "request_url",
    "payload",
    "ingested_at",
)

RACE_PAGE_COLUMNS = ("season", "round", *PAGE_COLUMNS[1:])


@contextmanager
def connect(config: DatabricksConfig | None = None):
    from databricks import sql

    config = config or databricks_config()
    connection = sql.connect(
        server_hostname=config.host,
        http_path=config.http_path,
        access_token=config.token,
    )
    try:
        yield connection
    finally:
        connection.close()


def ensure_schema(cursor, catalog: str, schema: str) -> None:
    cursor.execute(f"CREATE SCHEMA IF NOT EXISTS {catalog}.{schema}")


def ensure_table(cursor, table: str, ddl: str) -> None:
    cursor.execute(ddl.format(table=table))


def replace_season(cursor, table: str, season: int, pages: Iterable[Page]) -> int:
    """Delete a season's pages, then insert the ones just fetched.

    Delete-then-insert rather than append: re-running a season must be safe,
    and a partial mix of stale and fresh pages must never be observable. The
    delete runs even when there is nothing to insert, so a season that has
    legitimately lost its data does not keep stale rows.
    """
    cursor.execute(f"DELETE FROM {table} WHERE season = ?", [season])
    return _write_pages(cursor, table, list(pages), PAGE_COLUMNS)


def replace_race(
    cursor, table: str, season: int, round_number: int, pages: Iterable[Page]
) -> int:
    """Delete one race's pages, then insert the ones just fetched.

    The same guarantee as replace_season, scoped to a single race, so loading
    round 14 never touches rounds 1 to 13.
    """
    cursor.execute(
        f"DELETE FROM {table} WHERE season = ? AND round = ?", [season, round_number]
    )
    return _write_pages(cursor, table, list(pages), RACE_PAGE_COLUMNS)


def _write_pages(cursor, table: str, pages: list[Page], columns: Sequence[str]) -> int:
    if not pages:
        return 0

    ingested_at = dt.datetime.now(dt.UTC)
    written = 0
    for start in range(0, len(pages), INSERT_BATCH_SIZE):
        chunk = pages[start : start + INSERT_BATCH_SIZE]
        _insert_chunk(cursor, table, chunk, ingested_at, columns)
        written += len(chunk)
        log.debug("  %s: %d/%d pages", table, written, len(pages))

    return written


def _insert_chunk(
    cursor, table: str, pages: Sequence[Page], ingested_at, columns: Sequence[str]
) -> None:
    """Insert with bound parameters.

    Values are bound rather than interpolated because the payload is JSON:
    wall-to-wall double quotes and backslashes, and Databricks does not honour
    backslash escaping in string literals. String building produces invalid SQL
    on real data, not merely ugly SQL.
    """
    column_list = ", ".join(columns)
    row_marker = "(" + ", ".join("?" for _ in columns) + ")"
    markers = ", ".join(row_marker for _ in pages)

    parameters: list = []
    for page in pages:
        values = {
            "season": page.season,
            "round": page.round,
            "page_offset": page.offset,
            "page_limit": page.limit,
            "total_rows": page.total,
            "request_url": page.request_url,
            "payload": page.payload,
            "ingested_at": ingested_at,
        }
        parameters.extend(values[column] for column in columns)

    cursor.execute(f"INSERT INTO {table} ({column_list}) VALUES {markers}", parameters)
