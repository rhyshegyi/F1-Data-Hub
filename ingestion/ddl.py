"""Explicit DDL for the raw tables.

Written out rather than inferred so the dbt sources have a stable contract and
a schema change is a visible diff rather than a surprise.

Every endpoint lands in the same shape: paging metadata plus the response body
exactly as it arrived. The grain is one API page, not one race -- Jolpica
paginates over result rows, so a page can span several rounds.
"""

PAGE_DDL = """
CREATE TABLE IF NOT EXISTS {table} (
    season      INT,
    page_offset INT,
    page_limit  INT,
    total_rows  INT,
    request_url STRING,
    payload     STRING,
    ingested_at TIMESTAMP
)
"""

LOAD_STATE_DDL = """
CREATE TABLE IF NOT EXISTS {table} (
    endpoint    STRING,
    season      INT,
    last_round  INT,
    total_rows  INT,
    loaded_at   TIMESTAMP
)
"""

LOAD_STATE_TABLE = "raw_jolpica_load_state"
