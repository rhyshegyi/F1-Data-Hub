"""Raw-layer writes. The payload column is the thing worth protecting here."""

from conftest import FakeCursor, fixture_text

from ingestion.jolpica import Page
from ingestion.warehouse import INSERT_BATCH_SIZE, ensure_schema, replace_season

TABLE = "workspace.f1_raw.raw_jolpica_results"


def page(offset: int = 0, payload: str | None = None) -> Page:
    return Page(
        endpoint="results",
        season=2024,
        offset=offset,
        limit=100,
        total=479,
        request_url=f"https://api.jolpi.ca/ergast/f1/2024/results/?limit=100&offset={offset}",
        payload=payload if payload is not None else fixture_text("results_2024_offset0.json"),
    )


def test_payload_json_is_bound_not_interpolated():
    """JSON is wall-to-wall quotes and backslashes, and Databricks does not
    honour backslash escaping in string literals. Building this SQL by hand
    produces invalid statements on real data."""
    cursor = FakeCursor()
    payload = r'{"raceName": "Moody\'s \"GP\"", "path": "C:\temp"}'

    replace_season(cursor, TABLE, 2024, [page(payload=payload)])

    inserts = [(s, p) for s, p in cursor.calls if s.startswith("INSERT")]
    statement, parameters = inserts[0]
    assert payload not in statement, "payload must never reach the SQL text"
    assert payload in parameters


def test_a_season_is_deleted_before_it_is_reinserted():
    """A partial mix of stale and fresh pages must never be observable."""
    cursor = FakeCursor()

    replace_season(cursor, TABLE, 2024, [page()])

    kinds = [s.split()[0] for s in cursor.statements]
    assert kinds.index("DELETE") < kinds.index("INSERT")


def test_the_delete_is_scoped_to_one_season():
    cursor = FakeCursor()

    replace_season(cursor, TABLE, 2024, [page()])

    delete, parameters = next((s, p) for s, p in cursor.calls if s.startswith("DELETE"))
    assert "WHERE season = ?" in delete
    assert parameters == [2024]


def test_replacing_with_no_pages_still_clears_the_season():
    """A season that legitimately has no data must not keep old rows."""
    cursor = FakeCursor()

    written = replace_season(cursor, TABLE, 1993, [])

    assert written == 0
    assert [s.split()[0] for s in cursor.statements] == ["DELETE"]


def test_pages_are_written_in_batches():
    """Payloads are large -- a whole season in one statement is not sensible."""
    cursor = FakeCursor()
    pages = [page(offset=i * 100) for i in range(INSERT_BATCH_SIZE + 1)]

    written = replace_season(cursor, TABLE, 2024, pages)

    assert written == len(pages)
    assert len([s for s in cursor.statements if s.startswith("INSERT")]) == 2


def test_every_page_column_is_persisted():
    cursor = FakeCursor()

    replace_season(cursor, TABLE, 2024, [page(offset=300)])

    _, parameters = next((s, p) for s, p in cursor.calls if s.startswith("INSERT"))
    assert 2024 in parameters and 300 in parameters and 479 in parameters


def test_ensure_schema_is_idempotent_sql():
    cursor = FakeCursor()

    ensure_schema(cursor, "workspace", "f1_raw")

    assert cursor.statements == ["CREATE SCHEMA IF NOT EXISTS workspace.f1_raw"]
