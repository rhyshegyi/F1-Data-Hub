"""Race-by-race loading for laps and pit stops.

Jolpica only serves these one race at a time, and a season of laps is around
270 pages. So they load per race: only races newer than what's already loaded,
with progress recorded after every race so an interrupted backfill resumes at
the next race rather than the start of the season.
"""

import json

from conftest import FakeCursor, FakeResponse, RecordingSleep, fixture_text

from ingestion.endpoints import Endpoint
from ingestion.pipeline import run_seasons, season_rounds
from ingestion.state import Watermark, progress_name

SCHEMA = "workspace.f1_raw"
STATE_TABLE = f"{SCHEMA}.raw_jolpica_load_state"
LAPS = Endpoint("laps", "raw_jolpica_laps", first_season=1996, per_race=True)


def calendar(season: int, rounds: int) -> str:
    """A races response listing `rounds` races."""
    return json.dumps({"MRData": {
        "limit": "100", "offset": "0", "total": str(rounds),
        "RaceTable": {"season": str(season), "Races": [
            {"season": str(season), "round": str(r)} for r in range(1, rounds + 1)
        ]},
    }})


def laps_page(season: int, round_number: int, total: int = 2) -> str:
    body = json.loads(fixture_text("laps_2024_1_offset0.json"))
    body["MRData"].update(total=str(total), limit="100", offset="0")
    body["MRData"]["RaceTable"].update(season=str(season), round=str(round_number))
    return json.dumps(body)


class Routed:
    """A transport answering the calendar and each race's laps separately."""

    def __init__(self, season, rounds, *, empty_rounds=(), failing_rounds=()):
        self.season, self.rounds = season, rounds
        self.empty_rounds, self.failing_rounds = set(empty_rounds), set(failing_rounds)
        self.urls: list[str] = []

    def __call__(self, url):
        self.urls.append(url)
        if "/races/" in url:
            return FakeResponse(calendar(self.season, self.rounds))
        round_number = int(url.split(f"/{self.season}/")[1].split("/")[0])
        if round_number in self.failing_rounds:
            return FakeResponse("", status_code=429)
        return FakeResponse(laps_page(self.season, round_number, 0 if round_number in self.empty_rounds else 2))

    def lap_rounds(self) -> list[int]:
        return [int(u.split(f"/{self.season}/")[1].split("/")[0]) for u in self.urls if "/laps/" in u]


def run(transport, season, *, watermarks=None, latest=None, force=False, cursor=None):
    cursor = cursor or FakeCursor()
    loaded, failures = run_seasons(
        cursor, SCHEMA, [season],
        watermarks=watermarks if watermarks is not None else {},
        transport=transport, sleep=RecordingSleep(),
        latest_round_by_season={season: latest} if latest else None,
        force=force, endpoints=[LAPS],
    )
    return cursor, loaded, failures


def state_writes(cursor) -> list[tuple[str, int, int | None]]:
    """(endpoint, season, last_round) for every watermark written, in order."""
    return [
        (p[0], p[1], p[2]) for s, p in cursor.calls
        if s.startswith("INSERT") and STATE_TABLE in s
    ]


def test_a_seasons_races_come_from_its_calendar():
    transport = Routed(2024, 24)

    assert season_rounds(2024, transport=transport, sleep=RecordingSleep()) == list(range(1, 25))
    assert "/2024/races/" in transport.urls[0]


def test_only_races_after_the_watermark_are_fetched():
    """After round 14 the daily run fetches round 14's laps, not all 14 races."""
    transport = Routed(2026, 23)
    existing = {("laps", 2026): Watermark("laps", 2026, last_round=13, total_rows=100)}

    run(transport, 2026, watermarks=existing, latest=14)

    assert transport.lap_rounds() == [14]


def test_the_current_season_stops_at_the_latest_finished_race():
    """The calendar lists all 23 races; only 14 have been run."""
    transport = Routed(2026, 23)

    run(transport, 2026, latest=14)

    assert transport.lap_rounds() == list(range(1, 15))


def test_progress_is_recorded_after_every_race():
    transport = Routed(2019, 3)

    cursor, _, _ = run(transport, 2019)

    progress = [w for w in state_writes(cursor) if w[0] == progress_name("laps")]
    assert progress == [(progress_name("laps"), 2019, 1), (progress_name("laps"), 2019, 2), (progress_name("laps"), 2019, 3)]


def test_a_finished_season_is_marked_complete_once_every_race_is_loaded():
    transport = Routed(2019, 3)

    cursor, loaded, failures = run(transport, 2019)

    assert ("laps", 2019, 3) in state_writes(cursor)
    assert [w.endpoint for w in loaded] == ["laps"] and failures == []


def test_an_interrupted_season_resumes_at_the_next_race():
    """A backfill stopped after round 5 of 2019 carries on from round 6."""
    transport = Routed(2019, 8)
    existing = {(progress_name("laps"), 2019): Watermark(progress_name("laps"), 2019, last_round=5, total_rows=10)}

    run(transport, 2019, watermarks=existing)

    assert transport.lap_rounds() == [6, 7, 8]


def test_a_complete_past_season_makes_no_requests():
    transport = Routed(2019, 8)
    existing = {("laps", 2019): Watermark("laps", 2019, last_round=8, total_rows=10)}

    _, loaded, failures = run(transport, 2019, watermarks=existing)

    assert transport.urls == [] and loaded == [] and failures == []


def test_a_race_whose_laps_are_not_published_yet_is_retried_next_run():
    """Results can appear before laps. Marking round 14 as loaded with no laps
    would mean it is never fetched again."""
    transport = Routed(2026, 23, empty_rounds={14})
    existing = {("laps", 2026): Watermark("laps", 2026, last_round=13, total_rows=100)}

    cursor, loaded, failures = run(transport, 2026, watermarks=existing, latest=14)

    assert not [w for w in state_writes(cursor) if w[2] == 14]
    assert loaded == [] and failures == []


def test_a_past_race_with_no_data_is_absence_not_failure():
    """Some older races have no lap data. Waiting for it would stall forever."""
    transport = Routed(1997, 3, empty_rounds={2})

    cursor, _, failures = run(transport, 1997)

    assert ("laps", 1997, 3) in state_writes(cursor)
    assert failures == []


def test_a_failure_mid_season_keeps_the_races_already_loaded():
    transport = Routed(2019, 5, failing_rounds={4})

    cursor, loaded, failures = run(transport, 2019)

    writes = state_writes(cursor)
    assert (progress_name("laps"), 2019, 3) in writes
    assert not [w for w in writes if w[0] == "laps"], "the season is not complete"
    assert "laps" in failures[0] and loaded == []


def test_each_race_is_replaced_on_its_own():
    transport = Routed(2019, 2)

    cursor, _, _ = run(transport, 2019)

    deletes = [p for s, p in cursor.calls if s.startswith("DELETE") and "raw_jolpica_laps" in s]
    assert deletes == [[2019, 1], [2019, 2]]


def test_force_reloads_every_race():
    """For a post-race penalty: backfill --seasons 2026 --force."""
    transport = Routed(2026, 23)
    existing = {("laps", 2026): Watermark("laps", 2026, last_round=14, total_rows=100)}

    run(transport, 2026, watermarks=existing, latest=14, force=True)

    assert transport.lap_rounds() == list(range(1, 15))
