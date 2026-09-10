"""Pagination, throttling and backoff against the real Jolpica page shapes."""

import json

import pytest
from conftest import FakeResponse, FakeTransport, RecordingSleep, fixture_text

from ingestion.jolpica import JolpicaError, fetch_pages, max_round


def envelope(total: int, offset: int, limit: int) -> str:
    """A results-shaped page with the given paging metadata."""
    body = json.loads(fixture_text("results_2024_offset0.json"))
    body["MRData"].update(total=str(total), offset=str(offset), limit=str(limit))
    return json.dumps(body)


def test_paging_covers_every_row_then_stops():
    total = 479
    transport = FakeTransport([FakeResponse(envelope(total, o, 100)) for o in range(0, 500, 100)])

    pages = list(fetch_pages("results", 2024, transport=transport, sleep=RecordingSleep()))

    assert [p.offset for p in pages] == [0, 100, 200, 300, 400]
    assert len(transport.urls) == 5


def test_payload_is_stored_verbatim():
    """The raw layer's whole purpose. Re-serialising would defeat it."""
    text = fixture_text("results_2024_lastpage.json")
    transport = FakeTransport(FakeResponse(text))

    page = next(iter(fetch_pages("results", 2024, transport=transport, sleep=RecordingSleep())))

    assert page.payload == text


def test_limit_is_capped_at_the_api_maximum():
    """Jolpica silently returns 100 when asked for more; ask honestly instead."""
    transport = FakeTransport(FakeResponse(envelope(2, 0, 100)))

    list(fetch_pages("results", 2024, transport=transport, limit=500, sleep=RecordingSleep()))

    assert "limit=100" in transport.urls[0]


def test_season_with_no_data_yields_no_pages():
    """Qualifying does not exist before 1994. That is absence, not failure."""
    transport = FakeTransport(FakeResponse(fixture_text("qualifying_1993_empty.json")))

    pages = list(fetch_pages("qualifying", 1993, transport=transport, sleep=RecordingSleep()))

    assert pages == []


def test_page_records_its_paging_metadata():
    transport = FakeTransport(FakeResponse(fixture_text("results_2024_offset0.json")))

    page = next(iter(fetch_pages("results", 2024, transport=transport, sleep=RecordingSleep())))

    assert page.endpoint == "results"
    assert page.season == 2024
    assert page.total == 479
    assert page.request_url == transport.urls[0]


def test_rate_limited_request_is_retried_and_succeeds():
    sleep = RecordingSleep()
    transport = FakeTransport([
        FakeResponse("", status_code=429, headers={"Retry-After": "7"}),
        FakeResponse(envelope(1, 0, 100)),
    ])

    pages = list(fetch_pages("results", 2024, transport=transport, sleep=sleep))

    assert len(pages) == 1
    assert 7 in sleep.delays, "Retry-After must be honoured, not guessed at"


def test_persistent_rate_limiting_eventually_gives_up():
    """The season stays unwatermarked, so re-running is the recovery path."""
    transport = FakeTransport(FakeResponse("", status_code=429))

    with pytest.raises(JolpicaError, match="429"):
        list(fetch_pages("results", 2024, transport=transport, sleep=RecordingSleep()))


def test_client_errors_are_not_retried():
    transport = FakeTransport(FakeResponse("not found", status_code=404))

    with pytest.raises(JolpicaError):
        list(fetch_pages("results", 9999, transport=transport, sleep=RecordingSleep()))

    assert len(transport.urls) == 1, "a 404 will not fix itself"


def test_requests_are_throttled_between_pages():
    transport = FakeTransport([FakeResponse(envelope(200, o, 100)) for o in (0, 100)])
    sleep = RecordingSleep()

    list(fetch_pages("results", 2024, transport=transport, sleep=sleep))

    assert sleep.delays, "must pace itself against a 500/hour budget"


def test_max_round_reads_the_latest_round_in_a_payload():
    assert max_round(fixture_text("results_2024_lastpage.json")) == 24
    assert max_round(fixture_text("results_2024_offset0.json")) == 1


def test_max_round_is_none_when_the_payload_has_no_races():
    """The drivers endpoint is season-scoped, not round-scoped."""
    assert max_round(fixture_text("drivers_2024_offset0.json")) is None
