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

    pages = list(pages)
    if not pages:
        return 0

    ingested_at = dt.datetime.now(dt.UTC)
    written = 0
    for start in range(0, len(pages), INSERT_BATCH_SIZE):
        chunk = pages[start : start + INSERT_BATCH_SIZE]
        _insert_chunk(cursor, table, chunk, ingested_at)
        written += len(chunk)
        log.debug("  %s: %d/%d pages", table, written, len(pages))

    return written


def _insert_chunk(cursor, table: str, pages: Sequence[Page], ingested_at) -> None:
    """Insert with bound parameters.

    Values are bound rather than interpolated because the payload is JSON:
    wall-to-wall double quotes and backslashes, and Databricks does not honour
    backslash escaping in string literals. String building produces invalid SQL
    on real data, not merely ugly SQL.
    """
    column_list = ", ".join(PAGE_COLUMNS)
    row_marker = "(" + ", ".join("?" for _ in PAGE_COLUMNS) + ")"
    markers = ", ".join(row_marker for _ in pages)

    parameters: list = []
    for page in pages:
        parameters.extend(
            [
                page.season,
                page.offset,
                page.limit,
                page.total,
                page.request_url,
                page.payload,
                ingested_at,
            ]
        )

    cursor.execute(f"INSERT INTO {table} ({column_list}) VALUES {markers}", parameters)
