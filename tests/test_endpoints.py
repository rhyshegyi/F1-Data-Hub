"""Which endpoints carry data for which seasons."""

from ingestion.endpoints import ENDPOINTS, covering


def test_every_endpoint_has_a_distinct_raw_table():
    tables = [e.table for e in ENDPOINTS]
    assert len(tables) == len(set(tables))
    assert all(t.startswith("raw_jolpica_") for t in tables)


def test_qualifying_is_excluded_before_it_exists():
    """Jolpica has no qualifying data before 1994."""
    assert "qualifying" not in [e.name for e in covering(1993)]
    assert "qualifying" in [e.name for e in covering(1994)]


def test_the_championship_first_season_is_covered():
    assert [e.name for e in covering(1950)] == ["races", "results", "drivers"]


def test_a_modern_season_is_covered_by_everything():
    assert {e.name for e in covering(2026)} == {"races", "results", "qualifying", "drivers"}
