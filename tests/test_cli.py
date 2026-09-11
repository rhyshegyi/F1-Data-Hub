"""Season-range parsing for the backfill CLI."""

import pytest

from ingestion.__main__ import parse_seasons


def test_no_spec_covers_every_season_up_to_the_current_one():
    seasons = parse_seasons(None, 2026)

    assert seasons[0] == 1950
    assert seasons[-1] == 2026


def test_a_range_is_inclusive_at_both_ends():
    assert parse_seasons("2020-2023", 2026) == [2020, 2021, 2022, 2023]


def test_a_single_season_is_a_one_item_range():
    assert parse_seasons("2024", 2026) == [2024]


def test_a_backwards_range_is_rejected_rather_than_silently_empty():
    """`--seasons 2026-2020` is a typo, not a request to do nothing."""
    with pytest.raises(ValueError, match="2026-2020"):
        parse_seasons("2026-2020", 2026)


def test_a_nonsense_spec_is_rejected():
    with pytest.raises(ValueError):
        parse_seasons("last-five", 2026)


def test_summary_records_what_was_loaded(tmp_path):
    """The scheduled workflow reads this to decide whether dbt needs to run --
    a quiet day should cost one API call, not a full model rebuild."""
    import json

    from ingestion.__main__ import write_summary
    from ingestion.state import Watermark

    path = tmp_path / "summary.json"
    loaded = [
        Watermark("results", 2026, last_round=14, total_rows=280),
        Watermark("sprint", 2026, last_round=14, total_rows=120),
    ]

    write_summary(path, loaded, failures=[])

    summary = json.loads(path.read_text(encoding="utf-8"))
    assert summary["loaded"] == 2
    assert summary["source_rows"] == 400
    assert summary["endpoint_seasons"] == ["2026 results", "2026 sprint"]
    assert summary["failures"] == []


def test_summary_of_a_quiet_run_says_nothing_loaded(tmp_path):
    import json

    from ingestion.__main__ import write_summary

    path = tmp_path / "summary.json"
    write_summary(path, [], failures=[])

    assert json.loads(path.read_text(encoding="utf-8"))["loaded"] == 0


def test_summary_carries_failures(tmp_path):
    import json

    from ingestion.__main__ import write_summary

    path = tmp_path / "summary.json"
    write_summary(path, [], failures=["2026 driver_standings: HTTP 520"])

    assert json.loads(path.read_text(encoding="utf-8"))["failures"] == [
        "2026 driver_standings: HTTP 520"
    ]
