"""The Jolpica endpoints this pipeline ingests.

Adding an endpoint is one entry here plus a DDL constant and a dbt source --
deliberately, so extending coverage is a small, obvious diff.
"""

from __future__ import annotations

from dataclasses import dataclass

from .config import first_season


@dataclass(frozen=True)
class Endpoint:
    """One API path and the raw table its pages land in.

    `path` is the API path segment; `name` is what the watermark and the logs
    call it. They differ only where the API uses camelCase, so that the rest of
    the project can stay in snake_case.

    `first_season` records when the source actually starts carrying data.
    Requesting an earlier season returns a valid, empty response rather than an
    error, but skipping those requests saves calls against an hourly budget.

    `per_race` endpoints are fetched one race at a time. Jolpica refuses a
    season-wide request for them, and they are large enough that reloading a
    whole season after every race would waste hundreds of requests.
    """

    path: str
    table: str
    first_season: int | None = None
    name: str = ""
    per_race: bool = False

    def __post_init__(self):
        if not self.name:
            object.__setattr__(self, "name", self.path)

    def covers(self, season: int) -> bool:
        return season >= (self.first_season or first_season())


ENDPOINTS: tuple[Endpoint, ...] = (
    Endpoint("races", "raw_jolpica_races"),
    Endpoint("results", "raw_jolpica_results"),
    Endpoint("qualifying", "raw_jolpica_qualifying", first_season=1994),
    Endpoint("drivers", "raw_jolpica_drivers"),
    # Final championship classifications, taken from the source rather than
    # derived. Between 1950 and 1990 only a driver's best N results counted,
    # so summing points scored gives the wrong champion -- Prost outscored
    # Senna in 1988, and Hill outscored Surtees in 1964, yet neither won.
    Endpoint("driverStandings", "raw_jolpica_driver_standings", name="driver_standings"),
    # The constructors' championship did not exist until 1958.
    Endpoint(
        "constructorStandings", "raw_jolpica_constructor_standings",
        name="constructor_standings", first_season=1958,
    ),
    # Sprint races, from 2021. Originally left out as YAGNI, which the data
    # disproved: sprints award championship points, so without them the points
    # a driver is shown to have scored disagrees with the published standings
    # for every season from 2021 on.
    Endpoint("sprint", "raw_jolpica_sprint_results", first_season=2021),
    # Every driver's position and time on every lap, from 1996. Around 1,100
    # rows a race, so about 12 pages each.
    Endpoint("laps", "raw_jolpica_laps", first_season=1996, per_race=True),
    # Pit stops, from 2011: lap, stop number and duration.
    Endpoint("pitstops", "raw_jolpica_pit_stops", first_season=2011, name="pit_stops", per_race=True),
)

BY_NAME = {endpoint.name: endpoint for endpoint in ENDPOINTS}


def covering(season: int) -> tuple[Endpoint, ...]:
    """Endpoints that carry data for `season`, in ingestion order."""
    return tuple(endpoint for endpoint in ENDPOINTS if endpoint.covers(season))
