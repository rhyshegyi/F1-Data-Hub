"""Orchestration: what gets loaded, what gets skipped, what survives a failure."""

import pytest
from conftest import FakeCursor, FakeResponse, FakeTransport, RecordingSleep, fixture_text

from ingestion.endpoints import Endpoint, covering
from ingestion.jolpica import JolpicaError
from ingestion.pipeline import latest_completed_race, load_season, run_seasons
from ingestion.state import Watermark

CONFIG_TABLES = ("workspace", "f1_raw")


def transport_for(name: str) -> FakeTransport:
    return FakeTransport(FakeResponse(fixture_text(name)))


def test_latest_completed_race_reads_the_current_season_and_round():
    transport = transport_for("current_last_results.json")

    season, round_number = latest_completed_race(transport=transport)

    assert (season, round_number) == (2026, 13)
    assert "current/last/results" in transport.urls[0]


def test_loading_a_season_records_a_watermark_with_the_latest_round():
    cursor = FakeCursor()
    endpoint = Endpoint("results", "raw_jolpica_results")

    watermark = load_season(
        cursor, "workspace.f1_raw", endpoint, 2024,
        transport=transport_for("results_2024_lastpage.json"), sleep=RecordingSleep(),
    )

    assert watermark == Watermark("results", 2024, last_round=24, total_rows=479)


def test_loading_a_season_with_no_data_records_a_zero_watermark():
    """Qualifying before 1994 is absence, not failure -- and must not be retried
    on every subsequent run."""
    cursor = FakeCursor()
    endpoint = Endpoint("qualifying", "raw_jolpica_qualifying")

    watermark = load_season(
        cursor, "workspace.f1_raw", endpoint, 1993,
        transport=transport_for("qualifying_1993_empty.json"), sleep=RecordingSleep(),
    )

    assert watermark.total_rows == 0
    assert watermark.last_round is None


def test_one_failing_endpoint_does_not_sink_the_whole_run():
    """A 585-request backfill that aborts on the first hiccup is useless."""
    cursor = FakeCursor()

    def transport(url):
        if "qualifying" in url:
            return FakeResponse("", status_code=429)
        return FakeResponse(fixture_text("results_2024_offset0.json"))

    loaded, failures = run_seasons(
        cursor, "workspace.f1_raw", [2024], watermarks={},
        transport=transport, sleep=RecordingSleep(),
    )

    assert "qualifying" in failures[0]
    assert len(loaded) == len(covering(2024)) - 1, "every other endpoint must still load"


def test_seasons_already_watermarked_are_skipped():
    cursor = FakeCursor()
    existing = {
        (e.name, 2024): Watermark(e.name, 2024, 24, 1) for e in covering(2024)
    }

    loaded, failures = run_seasons(
        cursor, "workspace.f1_raw", [2024], watermarks=existing,
        transport=FakeTransport([]), sleep=RecordingSleep(),
    )

    assert loaded == [] and failures == []


def test_a_persistent_failure_raises_rather_than_watermarking():
    """An unwatermarked season is what makes the re-run resume."""
    cursor = FakeCursor()

    with pytest.raises(JolpicaError):
        load_season(
            cursor, "workspace.f1_raw", Endpoint("results", "raw_jolpica_results"), 2024,
            transport=FakeTransport(FakeResponse("", status_code=429)),
            sleep=RecordingSleep(),
        )


def test_a_roundless_endpoint_records_the_round_the_load_was_current_as_of():
    """`drivers` has no rounds of its own. Without borrowing the season's
    current round it watermarks as None, and every scheduled run reloads it."""
    cursor = FakeCursor()

    watermark = load_season(
        cursor, "workspace.f1_raw", Endpoint("drivers", "raw_jolpica_drivers"), 2026,
        transport=transport_for("drivers_2024_offset0.json"), sleep=RecordingSleep(),
        as_of_round=13,
    )

    assert watermark.last_round == 13


def test_a_quiet_week_writes_absolutely_nothing():
    """The scheduled run's whole justification. Every endpoint must skip,
    including the ones with no rounds of their own."""
    cursor = FakeCursor()
    existing = {
        (e.name, 2026): Watermark(e.name, 2026, last_round=13, total_rows=1)
        for e in covering(2026)
    }

    loaded, failures = run_seasons(
        cursor, "workspace.f1_raw", [2026], watermarks=existing,
        transport=FakeTransport([]), sleep=RecordingSleep(),
        latest_round_by_season={2026: 13},
    )

    assert loaded == [] and failures == []
    assert not [s for s in cursor.statements if s.startswith(("INSERT", "DELETE"))]


def test_the_request_url_uses_the_api_path_not_the_snake_case_name():
    """`driverStandings` is the API path; `driver_standings` is what the rest of
    the project calls it. Requesting the latter returns nothing."""
    cursor = FakeCursor()
    transport = FakeTransport(FakeResponse(fixture_text("drivers_2024_offset0.json")))

    load_season(
        cursor, "workspace.f1_raw",
        Endpoint("driverStandings", "raw_jolpica_driver_standings", name="driver_standings"),
        2024, transport=transport, sleep=RecordingSleep(),
    )

    assert "/driverStandings/" in transport.urls[0]
