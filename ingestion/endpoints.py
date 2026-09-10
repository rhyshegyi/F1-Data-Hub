"""The Jolpica endpoints this pipeline ingests.

Adding an endpoint is one entry here plus a DDL constant and a dbt source --
deliberately, so extending coverage is a small, obvious diff.

Sprint results (2021 onwards) are omitted: Phase 2 defines four staging models
and sprints are not among them.
"""

from __future__ import annotations

from dataclasses import dataclass

from .config import first_season


@dataclass(frozen=True)
class Endpoint:
    """One API path and the raw table its pages land in.

    `first_season` records when the source actually starts carrying data.
    Requesting an earlier season returns a valid, empty response rather than an
    error, but skipping those requests saves a few hundred calls against an
    hourly budget the backfill is already close to.
    """

    name: str
    table: str
    first_season: int | None = None


ENDPOINTS: tuple[Endpoint, ...] = (
    Endpoint("races", "raw_jolpica_races"),
    Endpoint("results", "raw_jolpica_results"),
    Endpoint("qualifying", "raw_jolpica_qualifying", first_season=1994),
    Endpoint("drivers", "raw_jolpica_drivers"),
)

BY_NAME = {endpoint.name: endpoint for endpoint in ENDPOINTS}


def covering(season: int) -> tuple[Endpoint, ...]:
    """Endpoints that carry data for `season`, in ingestion order."""
    return tuple(
        endpoint
        for endpoint in ENDPOINTS
        if season >= (endpoint.first_season or first_season())
    )
