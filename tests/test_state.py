"""The skip-or-load decision that keeps the scheduled run cheap."""

from conftest import FakeCursor

from ingestion.state import Watermark, needs_load, read_watermarks


def marks(*watermarks):
    return {(w.endpoint, w.season): w for w in watermarks}


def test_an_unloaded_season_needs_loading():
    assert needs_load("results", 2024, {}) is True


def test_a_completed_season_already_loaded_is_skipped():
    """This is what makes a rate-limited backfill resumable."""
    existing = marks(Watermark("results", 2024, last_round=24, total_rows=479))

    assert needs_load("results", 2024, existing) is False


def test_force_reloads_a_season_that_is_already_loaded():
    existing = marks(Watermark("results", 2024, last_round=24, total_rows=479))

    assert needs_load("results", 2024, existing, force=True) is True


def test_the_current_season_reloads_once_a_new_race_has_run():
    existing = marks(Watermark("results", 2026, last_round=13, total_rows=260))

    assert needs_load("results", 2026, existing, latest_round=14) is True


def test_the_current_season_is_skipped_when_no_new_race_has_run():
    """The whole point: a daily run on a quiet week must write nothing."""
    existing = marks(Watermark("results", 2026, last_round=13, total_rows=260))

    assert needs_load("results", 2026, existing, latest_round=13) is False


def test_a_season_loaded_with_no_rounds_still_counts_as_loaded():
    """The drivers endpoint has no rounds, so a null watermark is normal."""
    existing = marks(Watermark("drivers", 2024, last_round=None, total_rows=25))

    assert needs_load("drivers", 2024, existing) is False


def test_watermarks_are_read_back_keyed_by_endpoint_and_season():
    cursor = FakeCursor(rows=[("results", 2024, 24, 479), ("drivers", 2024, None, 25)])

    watermarks = read_watermarks(cursor, "cat.f1_raw.raw_jolpica_load_state")

    assert watermarks[("results", 2024)].last_round == 24
    assert watermarks[("drivers", 2024)].last_round is None
