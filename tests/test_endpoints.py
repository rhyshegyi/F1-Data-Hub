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
    """1950 has races, results, drivers and a drivers' championship -- but no
    constructors' title, which was not introduced until 1958."""
    assert [e.name for e in covering(1950)] == [
        "races", "results", "drivers", "driver_standings",
    ]


def test_the_constructors_championship_is_excluded_before_it_existed():
    assert "constructor_standings" not in [e.name for e in covering(1957)]
    assert "constructor_standings" in [e.name for e in covering(1958)]


def test_a_modern_season_is_covered_by_everything():
    assert {e.name for e in covering(2026)} == {
        "races", "results", "qualifying", "drivers",
        "driver_standings", "constructor_standings", "sprint",
    }


def test_sprints_are_excluded_before_they_existed():
    """Sprint races began in 2021 and carry championship points, so omitting
    them makes points scored disagree with the published standings."""
    assert "sprint" not in [e.name for e in covering(2020)]
    assert "sprint" in [e.name for e in covering(2021)]
